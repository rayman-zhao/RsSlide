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

    /// Thumbnail raster: the smallest pyramid layer whose long side reaches
    /// `maxSize`, returned untouched (native dimensions, tile-grid pitch) —
    /// scaling is the consumer's call. Pixel format rides on `tileTrait`:
    /// brightfield slides interleave RGB samples in a single channel,
    /// fluorescent ones carry one gray plane per channel.
    public func fetchThumbnailPixelData(maxSize: Int = 512, channel: Int = 0) -> LayerPixelData? {
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
        return pxdata
    }

    public func fetchThumbnailJPEGImage(maxSize: Int = 512, channel: Int = 0) -> [UInt8]? {
        guard let pxdata = fetchThumbnailPixelData(maxSize: maxSize, channel: channel) else {
            return nil
        }
        // JPEG consumers rely on the exact legacy box: both dimensions ≤ maxSize.
        let (fitWidth, fitHeight) = fittingSize(
            width: pxdata.width, height: pxdata.height, maxSize: maxSize)
        if (fitWidth, fitHeight) == (pxdata.width, pxdata.height) {
            return tjCompress(
                pxdata.pixels, tileTrait.tjPF, pxdata.width, pxdata.height, pxdata.pitch)
        }
        // scaleImage takes tight rows only — trim before scaling.
        let trimmed = trimmedPixelData(from: pxdata)
        let scaled = scaleImage(
            srcPixels: trimmed.pixels,
            srcWidth: trimmed.width,
            srcHeight: trimmed.height,
            destWidth: fitWidth,
            destHeight: fitHeight,
            channels: tileTrait.pixelFormat.rawValue)
        return tjCompress(scaled, tileTrait.tjPF, fitWidth, fitHeight)
    }
}

private func fittingSize(width: Int, height: Int, maxSize: Int) -> (Int, Int) {
    if width > height {
        return (maxSize, maxSize * height / width)
    }
    if width < height {
        return (maxSize * width / height, maxSize)
    }
    return (maxSize, maxSize)
}
