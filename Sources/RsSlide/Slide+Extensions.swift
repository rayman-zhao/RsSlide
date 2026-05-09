import Foundation
import LibJPEGTurbo
import RsHelper

enum TileCoordinateTrait {
    case valid(trimming: Bool)
    case virtual
    case invalid
}

extension Slide {
    func validate(coord: TileCoordinate) -> TileCoordinateTrait {
        guard 0..<tierCount ~= coord.tier else { return .invalid }

        if 0..<layerTileSize.count ~= coord.layer {
            let rows = layerTileSize[coord.layer].r
            let cols =  layerTileSize[coord.layer].c
            guard 0..<rows ~= coord.row && 0..<cols ~= coord.col else { return .invalid }
            guard rows - 1 == coord.row || cols - 1 == coord.col else { return .valid(trimming: false) }

            let tileWidth = tileTrait.size.w
            let tileHeight = tileTrait.size.h
            let trimmedWidth = layerImageSize[coord.layer].w - coord.col * tileWidth
            let trimmedHeight = layerImageSize[coord.layer].h - coord.row * tileHeight
            guard trimmedWidth < tileWidth || trimmedHeight < tileHeight else { return .valid(trimming: false) }

            return .valid(trimming: true)
        } else {
            return .virtual
        }
    }

    func fetchTrimmedTileImage(at coord: TileCoordinate) -> [UInt8]? {
        guard let pxdata = fetchPixelData(from: coord, to: coord) else { return nil }

        return tjCompress(pxdata.pixels, tileTrait.tjPF, pxdata.width, pxdata.height, pxdata.pitch)
    }

    func fetchVirtualTileImage(at coord: TileCoordinate) -> [UInt8]? {
        guard let from = baseLayerPixelData else { return nil }
        guard coord.layer >= from.layer else { return nil }

        let scale = Int(pow(Double(layerZoom), Double(coord.layer - from.layer)))
        let virtualLayerWidth = Int(ceil(Double(from.width) / Double(scale)))
        let virtualLayerHeight = Int(ceil(Double(from.height) / Double(scale)))
        let virtualLayerRows = Int(ceil(Double(virtualLayerHeight) / Double(tileTrait.size.h)))
        let virtualLayerCols = Int(ceil(Double(virtualLayerWidth) / Double(tileTrait.size.w)))
        guard 0..<virtualLayerRows ~= coord.row && 0..<virtualLayerCols ~= coord.col else { return nil }

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

        return tjCompress(pixels, tileTrait.tjPF, virtualTileWidth, virtualTileHeight)
    }

    func trimPixelData(from: (pixels: [UInt8], layer: Int, width: Int, pitch: Int, height: Int)) -> (pixels: [UInt8], layer: Int, width: Int, height: Int) {
        let rowBytes = from.width * tileTrait.pixelBytes
        guard rowBytes != from.pitch else { return (from.pixels, from.layer, from.width, from.height) }

        var trimmed = [UInt8](repeating: 0, count: from.height * rowBytes)
        from.pixels.withUnsafeBytes { srcBuf in
            for y in 0..<from.height {
                memcpy(&trimmed[y * rowBytes], srcBuf.baseAddress! + y * from.pitch, rowBytes)
            }
        }

        return (trimmed, from.layer, from.width, from.height)
    }

    func fetchPixelData(at layer: Int) -> (pixels: [UInt8], layer: Int, width: Int, pitch: Int, height: Int)? {
        guard 0..<layerImageSize.count ~= layer else { return nil }

        let from = TileCoordinate(layer: layer, row: 0, col: 0)
        let to = TileCoordinate(layer: layer, row: layerTileSize[layer].r - 1, col: layerTileSize[layer].c - 1)
        return fetchPixelData(from: from, to: to)
    }

    func fetchPixelData(from: TileCoordinate, to: TileCoordinate) -> (pixels: [UInt8], layer: Int, width: Int, pitch: Int, height: Int)? {
        guard case .valid = validate(coord: from), case .valid = validate(coord: to) else { return nil }
        let pixelLayer = from.layer
        guard pixelLayer == to.layer else { return nil }
        guard from.row <= to.row && from.col <= to.col else { return nil }
        guard tileTrait.sampleBits == 8 && tileTrait.compression == .jpeg else {
            log.error("Failed to fetch tile pixels. Only support JPEG format slide file.")
            return nil
        }

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
                let coord = TileCoordinate(layer: pixelLayer, row: row, col: col)
                guard let img = fetchTileRawImage(at: coord) else { continue }

                tj3Decompress8(
                    tj,
                    img,
                    img.count,
                    &pixels[(row - from.row) * tileHeight * pixelPitch + (col - from.col) * tileTrait.pitchBytes],
                    Int32(pixelPitch),
                    tileTrait.tjPF.rawValue
                )
            }
        }

        return (pixels, pixelLayer, width, pitch, height)
    }
}
