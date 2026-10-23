import Foundation
import LibJPEGTurbo
import LibTIFF
import LittleCMS
import RsFoundation

struct DCMPreview: InternalSlidePreview {
    let fileInfo: SlideFileInfo

    init(path: URL) {
        fileInfo = SlideFileInfo(url: path)
    }

    func fetchMacroJPEGImage() -> [UInt8]? {
        return nil
    }
}

final class DCM: InternalSlide {
    let fileInfo: SlideFileInfo

    lazy var id: UUID = {
        return UUID()
    }()
    let tierTrait = TierTrait()
    let channelTrait = [ChannelTrait()]
    var tileTrait: TileTrait = TileTrait(width: 0, height: 0)

    var scanObjective = 0.0
    var scanScale = 0.0
    let extendedXML: String = ""

    var layerImageSize: [(w: Int, h: Int)] = []
    var layerTileSize: [(r: Int, c: Int)] = []
    var layerZoom = 2

    lazy var topLayerPixelData = [fetchPixelData(at: layerTileSize.count - 1)]

    init?(path: URL) {
        fileInfo = SlideFileInfo(url: path)
        guard layerImageSize.count > 0 && tileTrait.size.w > 0 && tileTrait.size.h > 0 else {
            return nil
        }
    }

    deinit {
    }

    func fetchLabelJPEGImage() -> [UInt8]? {
        return nil
    }

    func fetchMacroJPEGImage() -> [UInt8]? {
        return nil
    }

    func fetchTileRawImage(for coord: TileCoordinate) -> [UInt8]? {
        guard case .valid = validate(coord) else { return nil }

        return nil
    }
}
