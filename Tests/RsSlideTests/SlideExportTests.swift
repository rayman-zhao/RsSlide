import Foundation
import FoundationXML
import Testing
import LibJPEGTurbo
import LibTIFF
import RsSlide

@Suite
struct ExportTests {
    init() async {
        await TIFFSetWarningHanlder { md, msg in
            print("TIFFWarning: \(md) - \(msg)")
        }
        await TIFFSetErrorHanlder { md, msg in
            print("TIFFError: \(md) - \(msg)")
        }
    }

    @Test
    func exportJPEG() throws {
        let fn = "MDSX/slide.mdsx"

        guard case .isSlide(let builder) = URL(filePath: fn, relativeTo: BASE).slideTrait else {
            fatalError("Invalid slide trait for \(fn)")
        }
        guard let s = builder.makeView() else {
            fatalError("Failed to create slide view for \(fn)")
        }

        let url = URL(filePath: "\(s.name)_export.jpg", directoryHint: .notDirectory, relativeTo: BASE)
        print("Exporting to \(url.filePath)")

        let st = Date()
        try s.save(as: url)
        let et = Date()
        print("Exported in \(et.timeIntervalSince(st)) seconds")

        let data = try Data(contentsOf: url)
        #expect(data.isJPEG)

        let jpeg = Array(data)
        let (w, h) = tjDecompressHeader(jpeg)
        #expect(w == s.layerImageSize[0].w || h == s.layerImageSize[0].h)
    }

    @Test
    func exportSVS() async throws {
        let fn = "MDSX/slide.mdsx"

        guard case .isSlide(let builder) = URL(filePath: fn, relativeTo: BASE).slideTrait else {
            fatalError("Invalid slide trait for \(fn)")
        }
        guard let s = builder.makeView() else {
            fatalError("Failed to create slide view for \(fn)")
        }

        let url = URL(filePath: "\(s.name)_export.svs", directoryHint: .notDirectory, relativeTo: BASE)
        print("Exporting to \(url.filePath)")

        let st = Date()
        try s.save(as: url)
        let et = Date()
        print("Exported in \(et.timeIntervalSince(st)) seconds")

        guard case .isSlide(let builder2) = url.slideTrait else {
            fatalError("Invalid slide trait for \(url)")
        }

        guard let s2 = builder2.makeView() else {
            fatalError("Failed to create slide view for \(url)")
        }

        try #require(s2.layerImageSize.count > 0)
        #expect(s2.layerImageSize[0] == s.layerImageSize[0])
        #expect(s2.layerTileSize[0] == s.layerTileSize[0])
        #expect("\(s2.tileTrait)" == "\(s.tileTrait)")
        #expect(s2.scanObjective == s.scanObjective)
        #expect(Int(s2.scanScale * 100) == Int(s.scanScale * 100))
        #expect(s2.layerZoom == s.layerZoom)

        var total = 0
        var cnt = 0
        for (li, layer) in s2.layerTileSize.enumerated() {
            total += layer.r * layer.c
            for rw in 0..<layer.r {
                for cl in 0..<layer.c {
                    let coord = TileCoordinate(layer: li, row: rw, col: cl)
                    guard let raw = s.fetchTileImage(at: coord) else { continue }
                    cnt += 1
                }
            }
        }
        #expect(cnt == total)

        let sp2 = builder2.makePreview()
        #expect(sp2.fetchMacroJPEGImage() != nil)
    }
}
