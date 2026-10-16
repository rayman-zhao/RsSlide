import Foundation
import FoundationXML
import LibJPEGTurbo
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
                "23SC-5-2.qptiff", "23SC-5-2", 4, 9, 96936, 79812, 40, 0.171625, true, true,
                ["DAPI", "FITC", "TRITC", "Cy5"]
            )
            // (
            //     "_20250228132506.qptiff", "_20250228132506", 15, 8, 15385, 44296, 20, 0.531915,
            //     false, false, []
            // ),
        ])
    func qptiffOpen(
        _ fn: String, _ name: String, _ channels: Int, _ levels: Int, _ width: Int, _ height: Int,
        _ objective: Int, _ scale: Double, _ hasLabel: Bool, _ hasMacro: Bool, _ bandNames: [String]
    ) async throws {
        print("Validating QPTIFF/\(fn)")
        let s = try qpOpen(fn)

        #expect(s.name == name)
        #expect(s.format == "QPTIFF")
        #expect(s.dataSize > 0)
        #expect(s.channelCount == channels)
        #expect(s.scanObjective == objective)
        #expect(abs(s.scanScale - scale) < 0.001)
        print("Slide GUID \(s.id), objective \(s.scanObjective), scale \(s.scanScale)")

        #expect(s.layerImageSize.count == levels)
        #expect(s.layerImageSize.count == s.layerTileSize.count)
        #expect(s.layerImageSize[0].w == width && s.layerImageSize[0].h == height)
        #expect(s.tileTrait.pixelFormat == .gray)
        #expect(s.tileTrait.compression == .jpeg)
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

        // Thumbnail comes from the gray top layer of tier 0.
        let thumbnail = try #require(s.fetchThumbnailJPEGImage(maxSize: 512))
        let (tw, th) = tjDecompressHeader(thumbnail)
        #expect(tw <= 512 && th <= 512)
        try Data(thumbnail).write(
            to: URL(
                filePath: "QPTIFF/\(name)_thumbnail.jpg", directoryHint: .notDirectory,
                relativeTo: BASE))

        #expect(s.topLayerPixelData != nil)
        #expect(s.topLayerPixelData[0]?.width == s.layerImageSize.last?.w)
        #expect(s.topLayerPixelData[0]?.height == s.layerImageSize.last?.h)

        // Bands are published as ScanProfile XML, same shape as the legacy C++ .dsmeta sidecar.
        let names = qpMatches(s.extendedXML, "<Name>([^<]*)</Name>")
        #expect(names.count == channels)
        if !bandNames.isEmpty {
            #expect(names == bandNames)
        }
        #expect(qpMatches(s.extendedXML, "<Color>([^<]*)</Color>").count == channels)
        if !s.extendedXML.isEmpty {
            _ = try #require(try? XMLDocument(xmlString: s.extendedXML))
        }

        // Beyond the stored levels, the generic virtual tile machinery serves gray tiles.
        let virtual = try #require(
            s.fetchTileImage(for: TileCoordinate(layer: s.layerTileSize.count, row: 0, col: 0)))
        let (vw, vh) = tjDecompressHeader(virtual)
        #expect(vw > 0 && vh > 0)
    }

    @Test(.serialized, arguments: ["23SC-5-2.qptiff", "_20250228132506.qptiff"])
    func qptiffTiles(_ fn: String) async throws {
        let s = try qpOpen(fn)
        let midRow = s.layerTileSize[0].r / 2
        let midCol = s.layerTileSize[0].c / 2
        let top = s.layerTileSize.count - 1

        for tier in 0..<s.tierCount {
            let mid = TileCoordinate(layer: 0, row: midRow, col: midCol, tier: tier)
            let raw = try #require(s.fetchTileRawImage(for: mid))
            #expect(Data(raw).isJPEG)
            #expect(tjDecompressHeader(raw).width == 512)
            #expect(tjDecompressHeader(raw).height == 512)

            // Deterministic regardless of the current TIFF directory position.
            #expect(s.fetchTileRawImage(for: mid) == raw)

            for coord in [
                mid,
                TileCoordinate(
                    layer: 0, row: s.layerTileSize[0].r - 1, col: s.layerTileSize[0].c - 1,
                    tier: tier),
                TileCoordinate(layer: top, row: 0, col: 0, tier: tier),
            ] {
                let img = try #require(s.fetchTileImage(for: coord))
                #expect(Data(img).isImage)
            }
        }

        // Every tier must resolve to its own directories, not a single shared one.
        let directories = try #require((s as? QPTIFF)?.bandDirectories)
        #expect(directories.count == s.tierCount)
        for tier in 1..<s.tierCount {
            #expect(directories[tier] != directories[0])
        }
    }

    /// Decodes the top layer of every band and composites them with the band colors
    /// taken from extendedXML, writing the images for manual inspection.
    @Test(.serialized, arguments: ["23SC-5-2.qptiff", "_20250228132506.qptiff"])
    func qptiffComposite(_ fn: String) async throws {
        let s = try qpOpen(fn)
        let names = qpMatches(s.extendedXML, "<Name>([^<]*)</Name>")
        let colors = qpMatches(s.extendedXML, "<Color>([^<]*)</Color>").compactMap { UInt32($0) }
        #expect(names.count == s.tierCount && colors.count == s.tierCount)

        let layer = s.layerTileSize.count - 1
        let tj = tj3Init(Int32(TJINIT_DECOMPRESS.rawValue))
        defer { tj3Destroy(tj) }

        var grays: [[UInt8]] = []
        var width = 0
        var height = 0
        for tier in 0..<s.tierCount {
            let tile = try #require(
                s.fetchTileImage(for: TileCoordinate(layer: layer, row: 0, col: 0, tier: tier)))
            let (w, h) = tjDecompressHeader(tile)
            #expect(w > 0 && h > 0)
            width = w
            height = h

            var gray = [UInt8](repeating: 0, count: w * h)
            #expect(tj3Decompress8(tj, tile, tile.count, &gray, Int32(w), TJPF_GRAY.rawValue) == 0)
            grays.append(gray)

            try Data(tjCompress(gray, TJPF_GRAY, w, h)).write(
                to: URL(
                    filePath: "QPTIFF/\(s.name)_band\(tier)_\(names[tier]).jpg",
                    directoryHint: .notDirectory, relativeTo: BASE))
        }

        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        // At whole-slide scale the bands must carry different signals.
        #expect(grays.dropFirst().contains { $0 != grays[0] })
        for i in 0..<(width * height) {
            var r = 0
            var g = 0
            var b = 0
            for tier in 0..<s.tierCount {
                let argb = colors[tier]
                let v = Int(grays[tier][i])
                r += Int((argb >> 16) & 0xFF) * v / 255
                g += Int((argb >> 8) & 0xFF) * v / 255
                b += Int(argb & 0xFF) * v / 255
            }
            rgb[i * 3] = UInt8(min(255, r))
            rgb[i * 3 + 1] = UInt8(min(255, g))
            rgb[i * 3 + 2] = UInt8(min(255, b))
        }

        try Data(tjCompress(rgb, TJPF_RGB, width, height)).write(
            to: URL(
                filePath: "QPTIFF/\(s.name)_composite.jpg", directoryHint: .notDirectory,
                relativeTo: BASE))
        print("Composite \(width)x\(height) of \(s.tierCount) bands written")
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

func qpMatches(_ s: String, _ pattern: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    return regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap {
        guard let r = Range($0.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
}
