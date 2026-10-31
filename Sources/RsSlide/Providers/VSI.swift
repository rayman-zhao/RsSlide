import Foundation
import RsFoundation

/// Olympus cellSens slide: the `.vsi` file is an OLE compound document holding
/// only metadata, while pixels live in tiled-JPEG `.ets` files under the
/// sibling `_basename_` folder (`stackN/frame_t.ets`, plus `blob_*` blocks for
/// extra images/channels).
struct VSIPreview: InternalSlidePreview {
    let fileInfo: SlideFileInfo

    init(path: URL) {
        fileInfo = SlideFileInfo(url: path)
    }

    func fetchMacroJPEGImage() -> [UInt8]? {
        return nil
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
