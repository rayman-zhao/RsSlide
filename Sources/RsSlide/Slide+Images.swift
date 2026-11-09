import Foundation
import LibJPEGTurbo
import MBL
import RsFoundation

/// Row-tight thumbnail raster from the pyramid layer best matching `maxSize`.
/// `isColor` mirrors the slide's pixel format: brightfield slides interleave
/// RGB samples in a single channel, fluorescent ones carry one gray plane per
/// channel (combine the per-channel planes with pseudo colors at the consumer).
public struct RasterImage {
    public var pixels: [UInt8]
    public var width: Int
    public var height: Int
    public var isColor: Bool
}

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

    public func fetchThumbnailRasterImage(maxSize: Int = 512, channel: Int = 0) -> RasterImage? {
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

        let trimmed = trimmedPixelData(from: pxdata)
        guard trimmed.width > 0, trimmed.height > 0 else { return nil }

        if (thumbnailWidth, thumbnailHeight) == (trimmed.width, trimmed.height) {
            return RasterImage(
                pixels: trimmed.pixels, width: trimmed.width, height: trimmed.height,
                isColor: tileTrait.pixelFormat == .rgb)
        }
        let scaled = scaleImage(
            srcPixels: trimmed.pixels,
            srcWidth: trimmed.width,
            srcHeight: trimmed.height,
            destWidth: thumbnailWidth,
            destHeight: thumbnailHeight,
            channels: tileTrait.pixelFormat.rawValue)
        return RasterImage(
            pixels: scaled, width: thumbnailWidth, height: thumbnailHeight,
            isColor: tileTrait.pixelFormat == .rgb)
    }

    public func fetchThumbnailJPEGImage(maxSize: Int = 512, channel: Int = 0) -> [UInt8]? {
        guard let raster = fetchThumbnailRasterImage(maxSize: maxSize, channel: channel) else {
            return nil
        }
        return tjCompress(raster.pixels, tileTrait.tjPF, raster.width, raster.height)
    }
}
