import Foundation
import LibJPEGTurbo
import MBL
import RsFoundation

extension Slide {
    public func fetchTileImage(for coord: TileCoordinate) -> [UInt8]? {
        switch validate(coord) {
        case .valid(trimming: false):
            return fetchTileRawImage(for: coord)
        case .valid(trimming: true):
            return fetchTrimmedTileImage(for: coord)
        case .virtual:
            return fetchVirtualTileImage(for: coord)
        case .invalid:
            return nil
        }
    }

    public func fetchThumbnailJPEGImage(maxSize: Int = 512, channel: Int = 0) -> [UInt8]? {
        guard 0..<channelTrait.count ~= channel else { return nil }

        // Find the most suitable layer for thumbnail generation.
        var layer = layerImageSize.count - 1
        while layer > 0 && layerImageSize[layer].w < maxSize && layerImageSize[layer].h < maxSize {
            layer -= 1
        }

        guard layer >= 0 else { return nil }
        guard
            let pxdata = (layer == layerImageSize.count - 1)
                ? topLayerPixelData[channel] : fetchPixelData(at: layer, channel: channel)
        else { return nil }

        var thumbnailWidth = maxSize
        var thumbnailHeight = maxSize
        if pxdata.width > pxdata.height {
            thumbnailHeight = thumbnailWidth * pxdata.height / pxdata.width
        } else if pxdata.width < pxdata.height {
            thumbnailWidth = thumbnailHeight * pxdata.width / pxdata.height
        }

        if (thumbnailWidth, thumbnailHeight) == (pxdata.width, pxdata.height) {
            return tjCompress(
                pxdata.pixels, tileTrait.tjPF, pxdata.width, pxdata.height, pxdata.pitch)
        } else {
            let trimmed = trimmedPixelData(from: pxdata)
            let thumbnail = scaleImage(
                srcPixels: trimmed.pixels,
                srcWidth: trimmed.width,
                srcHeight: trimmed.height,
                destWidth: thumbnailWidth,
                destHeight: thumbnailHeight,
                channels: tileTrait.pixelFormat.rawValue)

            return tjCompress(thumbnail, tileTrait.tjPF, thumbnailWidth, thumbnailHeight)
        }
    }
}
