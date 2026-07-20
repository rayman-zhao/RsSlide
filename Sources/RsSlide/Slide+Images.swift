import Foundation
import RsFoundation
import LibJPEGTurbo
import MBL

public extension Slide {
    func fetchTileImage(at coord: TileCoordinate) -> [UInt8]? {
        switch validate(coord: coord) {
            case .valid(trimming: false):
                return fetchTileRawImage(at: coord)
            case .valid(trimming: true):
                return fetchTrimmedTileImage(at: coord)
            case .virtual:
                return fetchVirtualTileImage(at: coord)
            case .invalid:
                return nil
        }
    }

    func fetchThumbnailJPEGImage(with maxSize: Int = 512) -> [UInt8]? {
        guard tileTrait.pixelFormat == .rgb
            && tileTrait.sampleBits == 8
            && tileTrait.compression == .jpeg else {
            log.error("Failed to fetch thumbnail JPEG image. Only support RGB24 JPEG format slide file.")
            return nil
        }

        // Find the most suitable layer for thumbnail generation.
        var layer = layerImageSize.count - 1
        while (layer > 0 && layerImageSize[layer].w < maxSize && layerImageSize[layer].h < maxSize) {
            layer -= 1
        }
        
        guard layer >= 0 else { return nil }
        guard let pxdata = (layer == layerImageSize.count - 1) ? baseLayerPixelData : fetchPixelData(at: layer) else { return nil }

        var thumbnailWidth = maxSize
        var thumbnailHeight = maxSize
        if pxdata.width > pxdata.height {
            thumbnailHeight = thumbnailWidth * pxdata.height / pxdata.width
        } else if pxdata.width < pxdata.height {
            thumbnailWidth = thumbnailHeight * pxdata.width / pxdata.height
        }

        if (thumbnailWidth, thumbnailHeight) == (pxdata.width, pxdata.height) {
            return tjCompress(pxdata.pixels, tileTrait.tjPF, pxdata.width, pxdata.height, pxdata.pitch)
        } else {
            let trimmed = trimPixelData(from: pxdata)
            let thumbnail = scaleImage(trimmed.pixels, trimmed.width, trimmed.height, thumbnailWidth, thumbnailHeight)
            return tjCompress(thumbnail, tileTrait.tjPF, thumbnailWidth, thumbnailHeight)
        }
    }
}
