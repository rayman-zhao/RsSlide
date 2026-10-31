import Foundation
import LibTIFF
import RsFoundation

/// Olympus cellSens slide: the `.vsi` file is a little-endian TIFF whose IFD 0
/// holds a JPEG overview of the glass slide.
struct VSIPreview: InternalSlidePreview {
    let fileInfo: SlideFileInfo

    init(path: URL) {
        fileInfo = SlideFileInfo(url: path)
    }

    func fetchMacroJPEGImage() -> [UInt8]? {
        #if os(Windows)
            guard let tiff = TIFFOpenW(fileInfo.mainPath.wideString, "rh") else { return nil }
        #else
            guard let tiff = TIFFOpen(fileInfo.mainPath, "rh") else { return nil }
        #endif
        defer { TIFFClose(tiff) }

        return TIFFReadJPEGImage(tiff, 0)
    }
}

final class VSI: InternalSlide {
    let fileInfo: SlideFileInfo
    let id: UUID
    let tierTrait = TierTrait()
    let channelTrait = [ChannelTrait()]
    let tileTrait: TileTrait

    let scanObjective: Double
    let scanScale: Double
    let extendedXML: String = ""

    let layerImageSize: [(w: Int, h: Int)]
    let layerTileSize: [(r: Int, c: Int)]

    lazy var topLayerPixelData = [fetchPixelData(at: layerTileSize.count - 1)]

    init?(path: URL) {
        fileInfo = SlideFileInfo(url: path)
        return nil
    }

    func fetchLabelJPEGImage() -> [UInt8]? {
        return nil
    }

    func fetchMacroJPEGImage() -> [UInt8]? {
        return nil
    }

    func fetchTileRawImage(for coord: TileCoordinate) -> [UInt8]? {
        return nil
    }
}
