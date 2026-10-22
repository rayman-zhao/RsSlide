import Foundation
import LibJPEGTurbo
import LibPNG
import RsFoundation

enum TileCoordinateValidation {
    case valid(trimming: Bool)
    case virtual
    case invalid
}

extension Slide {
    func validate(_ coordinate: TileCoordinate) -> TileCoordinateValidation {
        guard 0..<tierCount ~= coordinate.tier else { return .invalid }
        guard 0..<channelCount ~= coordinate.channel else { return .invalid }

        if 0..<layerTileSize.count ~= coordinate.layer {
            let rows = layerTileSize[coordinate.layer].r
            let cols = layerTileSize[coordinate.layer].c
            guard 0..<rows ~= coordinate.row && 0..<cols ~= coordinate.col else { return .invalid }
            guard rows - 1 == coordinate.row || cols - 1 == coordinate.col else {
                return .valid(trimming: false)
            }

            let tileWidth = tileTrait.size.w
            let tileHeight = tileTrait.size.h
            let trimmedWidth = layerImageSize[coordinate.layer].w - coordinate.col * tileWidth
            let trimmedHeight = layerImageSize[coordinate.layer].h - coordinate.row * tileHeight
            guard trimmedWidth < tileWidth || trimmedHeight < tileHeight else {
                return .valid(trimming: false)
            }

            return .valid(trimming: true)
        } else {
            return .virtual
        }
    }

    func fetchTrimmedTileImage(for coord: TileCoordinate) -> [UInt8]? {
        guard let pxdata = fetchPixelData(from: coord, to: coord) else { return nil }

        switch tileTrait.compression {
        case .jpeg:
            return tjCompress(
                pxdata.pixels, tileTrait.tjPF, pxdata.width, pxdata.height, pxdata.pitch)
        case .png:
            return pngCompress(
                pxdata.pixels, tileTrait.pngPF, pxdata.width, pxdata.height, pxdata.pitch)
        default:
            return nil
        }
    }

    func fetchVirtualTileImage(for coord: TileCoordinate) -> [UInt8]? {
        guard let from = topLayerPixelData[coord.channel] else { return nil }
        guard coord.layer >= from.layer else { return nil }

        let scale = Int(pow(Double(layerZoom), Double(coord.layer - from.layer)))
        let virtualLayerWidth = Int(ceil(Double(from.width) / Double(scale)))
        let virtualLayerHeight = Int(ceil(Double(from.height) / Double(scale)))
        let virtualLayerRows = Int(ceil(Double(virtualLayerHeight) / Double(tileTrait.size.h)))
        let virtualLayerCols = Int(ceil(Double(virtualLayerWidth) / Double(tileTrait.size.w)))
        guard 0..<virtualLayerRows ~= coord.row && 0..<virtualLayerCols ~= coord.col else {
            return nil
        }

        let virtualTileX = coord.col * tileTrait.size.w
        let virtualTileY = coord.row * tileTrait.size.h
        let virtualTileWidth = min(virtualLayerWidth - virtualTileX, tileTrait.size.w)
        let virtualTileHeight = min(virtualLayerHeight - virtualTileY, tileTrait.size.h)
        let pixelBytes = tileTrait.pixelBytes
        let rowBytes = virtualTileWidth * pixelBytes
        var pixels = [UInt8](repeating: 0, count: rowBytes * virtualTileHeight)

        from.pixels.withUnsafeBytes { srcBuf in
            let srcBase = srcBuf.baseAddress!
            let srcPitch = from.pitch
            // Optimize by copying row by row if possible
            if scale == 1 {
                // Direct block copy for scale 1
                for y in 0..<virtualTileHeight {
                    let srcRow = (virtualTileY + y) * srcPitch + virtualTileX * pixelBytes
                    let dstRow = y * rowBytes
                    memcpy(&pixels[dstRow], srcBase + srcRow, rowBytes)
                }
            } else {
                // Fallback: per-pixel copy for scale > 1
                var dstOffset = 0
                for y in 0..<virtualTileHeight {
                    let srcRow = (virtualTileY + y) * scale * srcPitch
                    for x in 0..<virtualTileWidth {
                        let srcOffset = srcRow + (virtualTileX + x) * scale * pixelBytes

                        memcpy(&pixels[dstOffset], srcBase + srcOffset, pixelBytes)
                        dstOffset += pixelBytes
                    }
                }
            }
        }

        switch tileTrait.compression {
        case .jpeg:
            return tjCompress(pixels, tileTrait.tjPF, virtualTileWidth, virtualTileHeight)
        case .png:
            return pngCompress(pixels, tileTrait.pngPF, virtualTileWidth, virtualTileHeight)
        default:
            return nil
        }
    }

    func trimmedPixelData(from: LayerPixelData) -> LayerPixelData {
        let rowBytes = from.width * tileTrait.pixelBytes
        guard rowBytes != from.pitch else { return from }

        var trimmed = [UInt8](repeating: 0, count: from.height * rowBytes)
        from.pixels.withUnsafeBytes { srcBuf in
            for y in 0..<from.height {
                memcpy(&trimmed[y * rowBytes], srcBuf.baseAddress! + y * from.pitch, rowBytes)
            }
        }

        return LayerPixelData(
            pixels: trimmed, layer: from.layer, width: from.width, pitch: rowBytes,
            height: from.height)
    }

    func fetchPixelData(at layer: Int, channel: Int = 0) -> LayerPixelData? {
        guard 0..<layerImageSize.count ~= layer else { return nil }

        let from = TileCoordinate(layer: layer, row: 0, col: 0, channel: channel)
        let to = TileCoordinate(
            layer: layer, row: layerTileSize[layer].r - 1, col: layerTileSize[layer].c - 1,
            channel: channel)
        return fetchPixelData(from: from, to: to)
    }

    func fetchPixelData(from: TileCoordinate, to: TileCoordinate) -> LayerPixelData? {
        guard
            tileTrait.sampleBits == 8
                && (tileTrait.compression == .jpeg || tileTrait.compression == .png)
        else {
            log.error("Failed to fetch tile pixels. Only support JPEG/PNG format slide file.")
            return nil
        }
        guard case .valid = validate(from), case .valid = validate(to) else { return nil }
        let pixelLayer = from.layer
        guard pixelLayer == to.layer else { return nil }
        guard from.row <= to.row && from.col <= to.col else { return nil }

        let tileWidth = tileTrait.size.w
        let tileHeight = tileTrait.size.h
        let pixelWidth = (to.col - from.col + 1) * tileWidth
        let pixelPitch = (to.col - from.col + 1) * tileTrait.pitchBytes
        let pixelHeight = (to.row - from.row + 1) * tileHeight

        var pixels = [UInt8](repeating: 0, count: pixelPitch * pixelHeight)
        var trimWidth = 0
        var trimHeight = 0
        if to.row == layerTileSize[to.layer].r - 1 {
            trimHeight = (to.row + 1) * tileHeight - layerImageSize[pixelLayer].h
        }
        if to.col == layerTileSize[to.layer].c - 1 {
            trimWidth = (to.col + 1) * tileWidth - layerImageSize[pixelLayer].w
        }
        let width = pixelWidth - trimWidth
        let pitch = pixelPitch
        let height = pixelHeight - trimHeight

        let tj = tj3Init(TJINIT_DECOMPRESS.rawValue)
        defer { tj3Destroy(tj) }

        for row in from.row...to.row {
            for col in from.col...to.col {
                let coord = TileCoordinate(
                    layer: pixelLayer, row: row, col: col, tier: from.tier, channel: from.channel)
                guard let img = fetchTileRawImage(for: coord) else { continue }

                let offset =
                    (row - from.row) * tileHeight * pixelPitch
                    + (col - from.col) * tileTrait.pitchBytes

                if tileTrait.compression == .png {
                    pngDecompress(img, &pixels[offset], tileTrait.pngPF, pixelPitch)
                } else {
                    tj3Decompress8(
                        tj, img, img.count, &pixels[offset], Int32(pixelPitch),
                        tileTrait.tjPF.rawValue)
                }
            }
        }

        return LayerPixelData(
            pixels: pixels, layer: pixelLayer, width: width, pitch: pitch, height: height)
    }
}
