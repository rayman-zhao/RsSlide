import Foundation
import LibDICOM
import RsFoundation

struct DCMPreview: InternalSlidePreview {
    let fileInfo: SlideFileInfo

    init(path: URL) {
        fileInfo = SlideFileInfo(url: path)
    }

    func fetchMacroJPEGImage() -> [UInt8]? {
        for child in fileInfo.children where child.pathExtension.lowercased() == "dcm" {
            if let file = DCMFile.open(child), file.role == "OVERVIEW",
                let frame = file.readRawFrame(1)
            {
                return frame
            }
        }

        return nil
    }
}

/// A folder of VL whole-slide-microscopy DICOM instances: the VOLUME instances
/// sorted by pixel-matrix area form the layer pyramid, LABEL/OVERVIEW provide
/// the associated JPEG images.
///
/// Pyramid tiles are whatever codestream the scanner encapsulated (HEVC for the
/// SQRAY sample, declared as JPEG Baseline) and are passed through undecoded;
/// only the label/macro JPEGs are directly usable, the shared pixel paths that
/// would need decoding (edge-tile trimming, virtual layers, thumbnail) return
/// nil until an HEVC decoder is plugged in.
final class DCM: InternalSlide {
    private let studyUID: String
    private let layerFile: [DCMFile]
    private let labelFile: DCMFile?
    private let overviewFile: DCMFile?

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

        var foundStudy: String?
        var volumes: [(file: DCMFile, w: Int, h: Int)] = []
        var foundLabelFile: DCMFile?
        var foundOverviewFile: DCMFile?
        for child in fileInfo.children where child.pathExtension.lowercased() == "dcm" {
            guard let file = DCMFile.open(child), let study = file.studyUID else { continue }
            if foundStudy == nil { foundStudy = study } else if foundStudy != study { continue }

            switch file.role {
            case "VOLUME":
                if let w = file.intValue(DCMTag.totalPixelMatrixColumns),
                    let h = file.intValue(DCMTag.totalPixelMatrixRows),
                    w > 0, h > 0
                {
                    volumes.append((file, w, h))
                }
            case "LABEL":
                if foundLabelFile == nil { foundLabelFile = file }
            case "OVERVIEW":
                if foundOverviewFile == nil { foundOverviewFile = file }
            default:
                continue
            }
        }

        // The Study UID groups the folder's instances into one slide; without it
        // there is nothing to build a slide from.
        guard let foundStudy, !volumes.isEmpty else { return nil }
        volumes.sort { $0.w * $0.h > $1.w * $1.h }

        studyUID = foundStudy
        layerFile = volumes.map { $0.file }
        labelFile = foundLabelFile
        overviewFile = foundOverviewFile
        id = Data(foundStudy.utf8).hashUUID

        let base = volumes[0].file
        guard let frameRows = base.intValue(DCMTag.rows),
            let frameCols = base.intValue(DCMTag.columns), frameRows > 0, frameCols > 0
        else { return nil }
        tileTrait = TileTrait(width: frameCols, height: frameRows)

        scanObjective =
            base.decimalValue(
                DCMTag.objectiveLensPower, in: base.itemDataset(DCMTag.opticalPathSequence)) ?? 0
        let spacing =
            base.decimalValue(
                DCMTag.pixelSpacing,
                in: base.itemDataset(
                    DCMTag.pixelMeasuresSequence,
                    in: base.itemDataset(DCMTag.sharedFunctionalGroupsSequence)))
            ?? base.decimalValue(DCMTag.pixelSpacing) ?? 0
        scanScale = spacing * 1000

        layerImageSize = volumes.map { ($0.w, $0.h) }
        layerTileSize = volumes.map {
            (
                Int(ceil(Double($0.h) / Double(frameRows))),
                Int(ceil(Double($0.w) / Double(frameCols)))
            )
        }
    }

    func fetchLabelJPEGImage() -> [UInt8]? {
        return labelFile?.readRawFrame(1)
    }

    func fetchMacroJPEGImage() -> [UInt8]? {
        return overviewFile?.readRawFrame(1)
    }

    func fetchTileRawImage(for coord: TileCoordinate) -> [UInt8]? {
        guard case .valid = validate(coord) else { return nil }
        let file = layerFile[coord.layer]
        guard let number = file.frameNumber(column: UInt32(coord.col), row: UInt32(coord.row))
        else { return nil }
        return file.readRawFrame(number)
    }
}
