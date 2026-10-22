import Foundation
import FoundationXML
import LibJPEGTurbo
import LibPNG
import LibTIFF
import Testing

@testable import RsSlide

@Suite
struct QPTIFFTests {
    init() async {
        await TIFFSetWarningHandler { _, _ in }
    }

    @Test(
        .serialized,
        arguments: [
            (
                "23SC-5-2.qptiff", "23SC-5-2",
                4, 9, 96936, 79812, 40, 0.171625, true, true,
                ["DAPI", "FITC", "TRITC", "Cy5"],
                "2D53BA1A-FC3E-5E92-AF1C-D1956ED3809B"
            ),
            (
                "02914056_20230103124040.qptiff", "02914056_20230103124040",
                3, 5, 15577, 12998, 80, 0.125, true, true,
                ["DAPI", "FITC", "TRITC"],
                "62B0EA7B-E759-40FB-941E-E038852896B0"
            ),
            (
                "02914056_20230103131001.qptiff", "02914056_20230103131001",
                3, 5, 19925, 20336, 80, 0.125, true, true,
                ["DAPI", "FITC", "TRITC"],
                "73C34262-E996-40AD-9D79-273995A7DA72"
            ),
            (
                "derm-FITC_20231005163648.qptiff", "derm-FITC_20231005163648",
                1, 5, 17735, 22175, 40, 1.0, true, true,
                ["FITC"],
                "BA4264C6-A9F4-49C4-9C88-CD2A9EA005ED"
            ),
            (
                "胰岛-绿橙红-01-EDF.qptiff", "胰岛-绿橙红-01-EDF",
                3, 5, 24456, 25988, 80, 0.134, true, true,
                ["DAPI", "FITC", "TRITC"],
                "5CE04553-5008-49DA-A862-A9F940A63609"
            ),
            (
                "bmp-qptiff.qptiff", "bmp-qptiff",
                3, 3, 4406, 3686, 20, 0.5, true, true,
                ["DAPI", "FITC", "TRITC"],
                "4FA05DD3-0F6D-48F3-BE57-C48F29FF6E90"
            ),
            (
                "20260513152446-24.qptiff", "20260513152446-24",
                4, 9, 119824, 65652, 40, 0.173337, true, true,
                ["DAPI", "FITC", "TRITC", "CY5"],
                "45366061-4D4F-5000-8529-4462136B0ED2"
            ),
            (
                "202404171225-3fl.qptiff", "202404171225-3fl",
                3, 5, 17876, 16799, 20, 0.5, true, true,
                ["DAPI", "FITC", "TRITC"],
                "7859AEDF-013F-402A-A463-55943A566367"
            ),
            (
                "20240417-4FL.qptiff", "20240417-4FL",
                15, 6, 15672, 14955, 20, 1.0, false, false,
                [
                    "1B-LED-ch", "1G-LED-ch", "1R-LED-ch",
                    "2B-LED-ch", "2G-LED-ch", "2R-LED-ch",
                    "3B-LED-ch", "3G-LED-ch", "3R-LED-ch",
                    "4B-LED-ch", "4G-LED-ch", "4R-LED-ch",
                    "5B-LED-ch", "5G-LED-ch", "5R-LED-ch",
                ],
                "C4D514B2-91F2-414A-B8F1-264F067C83B8"
            ),
            (
                "_20250228132506.qptiff", "_20250228132506",
                15, 8, 15385, 44296, 20, 0.531915, false, false,
                [
                    "C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8", "C9", "C10", "C11", "C12",
                    "C13", "C14", "C15",
                ],
                "2338B783-C995-4EBC-A037-038193A0573A"
            ),
        ])
    func qptiffOpen(
        _ fn: String, _ name: String, _ channels: Int, _ levels: Int, _ width: Int, _ height: Int,
        _ objective: Double, _ scale: Double, _ hasLabel: Bool, _ hasMacro: Bool,
        _ bandNames: [String], _ id: String
    ) async throws {
        print("Validating QPTIFF/\(fn)")
        let s = try qpOpen(fn)

        #expect(s.name == name)
        #expect(s.format == "QPTIFF")
        #expect(s.dataSize > 0)
        #expect(s.channelTrait.count == channels)
        #expect(s.channelTrait.map(\.name) == bandNames)
        #expect(s.channelTrait.allSatisfy { $0.pseudoColorRGB >= 0 })
        #expect(s.scanObjective == objective)
        #expect(abs(s.scanScale - scale) < 0.001)
        print("Slide GUID \(s.id), objective \(s.scanObjective), scale \(s.scanScale)")
        #expect(s.id.uuidString == id)

        #expect(s.layerImageSize.count == levels)
        #expect(s.layerImageSize.count == s.layerTileSize.count)
        #expect(s.layerImageSize[0].w == width && s.layerImageSize[0].h == height)
        #expect(s.tileTrait.pixelFormat == .gray)
        #expect(s.tileTrait.compression == .jpeg || s.tileTrait.compression == .png)
        #expect(s.tileTrait.size.w == 512 && s.tileTrait.size.h == 512)
        #expect([2, 4].contains(s.layerZoom))
        for i in 1..<s.layerImageSize.count {
            let w = Int(ceil(Double(s.layerImageSize[i - 1].w) / Double(s.layerZoom)))
            let h = Int(ceil(Double(s.layerImageSize[i - 1].h) / Double(s.layerZoom)))
            #expect(0...1 ~= w - s.layerImageSize[i].w)
            #expect(0...1 ~= h - s.layerImageSize[i].h)
        }
        for (i, size) in s.layerImageSize.enumerated() {
            print(
                "Layer \(i) \(size.w)x\(size.h) in \(s.layerTileSize[i].r)-\(s.layerTileSize[i].c)")
        }

        if hasLabel {
            let img = Data(try #require(s.fetchLabelJPEGImage()))
            #expect(img.isJPEG)
            try img.write(
                to: URL(
                    filePath: "QPTIFF/\(name)_label.jpg", directoryHint: .notDirectory,
                    relativeTo: BASE))
        } else {
            #expect(s.fetchLabelJPEGImage() == nil)
        }

        if hasMacro {
            let img = Data(try #require(s.fetchMacroJPEGImage()))
            #expect(img.isJPEG)
            try img.write(
                to: URL(
                    filePath: "QPTIFF/\(name)_macro.jpg", directoryHint: .notDirectory,
                    relativeTo: BASE))
        } else {
            #expect(s.fetchMacroJPEGImage() == nil)
        }

        #expect(s.channelTrait.count == channels)
        // #expect(s.bands.map(\.name) == bandNames)

        // Thumbnail comes from the gray top layer of tier 0.
        for channel in 0..<s.channelTrait.count {
            let thumbnail = try #require(s.fetchThumbnailJPEGImage(maxSize: 512, channel: channel))
            let (tw, th) = tjDecompressHeader(thumbnail)
            #expect(tw <= 512 && th <= 512)
            try Data(thumbnail).write(
                to: URL(
                    filePath: "QPTIFF/\(name)_thumbnail_\(channel).jpg",
                    directoryHint: .notDirectory,
                    relativeTo: BASE))
        }

        #expect(
            s.topLayerPixelData.allSatisfy({
                $0 != nil && $0!.width == s.layerImageSize.last?.w
                    && $0!.height == s.layerImageSize.last?.h
            }))

        // // Beyond the stored levels, the generic virtual tile machinery serves gray tiles.
        for channel in 0..<s.channelTrait.count {
            let virtual = try #require(
                s.fetchTileImage(
                    for: TileCoordinate(
                        layer: s.layerTileSize.count, row: 0, col: 0, channel: channel))
            )
            let (vw, vh) =
                s.tileTrait.compression == .jpeg
                ? tjDecompressHeader(virtual) : pngDecompressHeader(virtual)
            #expect(vw > 0 && vh > 0)
        }
    }
}

private enum QPTIFFTestError: Error {
    case notASlide(String)
}

func qpOpen(_ fn: String) throws -> Slide {
    let trait = URL(filePath: "QPTIFF/\(fn)", relativeTo: BASE).slideKind
    guard case .slide(let builder) = trait else {
        throw QPTIFFTestError.notASlide("QPTIFF/\(fn)")
    }
    return try #require(builder.makeSlide())
}
