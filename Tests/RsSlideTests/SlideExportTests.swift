import Foundation
import FoundationXML
import LibJPEGTurbo
import LibTIFF
import RsSlide
import Testing

@Suite
struct ExportTests {
    init() async {
        await TIFFSetWarningHandler { md, msg in
            print("TIFFWarning: \(md) - \(msg)")
        }
        await TIFFSetErrorHandler { md, msg in
            print("TIFFError: \(md) - \(msg)")
        }
    }

    @Test
    func exportJPEG() throws {
        let fn = "MDSX/slide.mdsx"

        guard case .slide(let builder) = URL(filePath: fn, relativeTo: BASE).slideKind else {
            fatalError("Invalid slide trait for \(fn)")
        }
        guard let s = builder.makeSlide() else {
            fatalError("Failed to create slide view for \(fn)")
        }

        let url = URL(
            filePath: "\(s.name)_crop.jpg", directoryHint: .notDirectory, relativeTo: BASE)
        print("Cropping to \(url.filePath)")

        let left = s.tileTrait.size.w * 4 / 3
        let top = s.tileTrait.size.h * 7 / 4
        let width = s.layerImageSize[0].w - left * 2
        let height = s.layerImageSize[0].h - top * 2
        let rect = CGRect(x: left, y: top, width: width, height: height)

        let st = Date()
        try s.crop(rect: rect, to: url)
        let et = Date()
        print("Cropped in \(et.timeIntervalSince(st)) seconds")

        let data = try Data(contentsOf: url)
        #expect(data.isJPEG)

        let jpeg = Array(data)
        let (w, h) = tjDecompressHeader(jpeg)
        #expect(w == width || h == height)
    }

    @Test
    func exportTIFF() throws {
        let fn = "KFB/1021754 (2).tif"

        guard case .slide(let builder) = URL(filePath: fn, relativeTo: BASE).slideKind else {
            fatalError("Invalid slide trait for \(fn)")
        }
        guard let s = builder.makeSlide() else {
            fatalError("Failed to create slide view for \(fn)")
        }

        let url = URL(
            filePath: "\(s.name)_crop.tif", directoryHint: .notDirectory, relativeTo: BASE)
        print("Cropping to \(url.filePath)")

        let left = s.layerImageSize[0].w / 4
        let top = s.layerImageSize[0].h / 4
        let width = s.layerImageSize[0].w / 2
        let height = s.layerImageSize[0].h / 2
        let rect = CGRect(x: left, y: top, width: width, height: height)

        let st = Date()
        try s.crop(rect: rect, to: url)
        let et = Date()
        print("Cropped in \(et.timeIntervalSince(st)) seconds")

        #if os(Windows)
            guard let tiff = TIFFOpenW(url.filePath.wideString, "r") else {
                fatalError("Failed to open TIFF export for validation")
            }
        #else
            guard let tiff = TIFFOpen(url.filePath, "r") else {
                fatalError("Failed to open TIFF export for validation")
            }
        #endif
        defer { TIFFClose(tiff) }

        let w: UInt32? = TIFFGetField(tiff, TIFFTAG_IMAGEWIDTH)
        let h: UInt32? = TIFFGetField(tiff, TIFFTAG_IMAGELENGTH)
        let rowsPerStrip: UInt32? = TIFFGetField(tiff, TIFFTAG_ROWSPERSTRIP)
        #expect(w == UInt32(width))
        #expect(h == UInt32(height))
        #expect(rowsPerStrip == UInt32(s.tileTrait.size.h))
    }

    @Test
    func exportSVS() async throws {
        let fn = "MDSX/slide.mdsx"

        guard case .slide(let builder) = URL(filePath: fn, relativeTo: BASE).slideKind else {
            fatalError("Invalid slide trait for \(fn)")
        }
        guard let s = builder.makeSlide() else {
            fatalError("Failed to create slide view for \(fn)")
        }

        let url = URL(
            filePath: "\(s.name)_convert.svs", directoryHint: .notDirectory, relativeTo: BASE)
        print("Converting to \(url.filePath)")

        let st = Date()
        try s.convert(to: url)
        let et = Date()
        print("Converted in \(et.timeIntervalSince(st)) seconds")

        guard case .slide(let builder2) = url.slideKind else {
            fatalError("Invalid slide trait for \(url)")
        }

        guard let s2 = builder2.makeSlide() else {
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
                    guard s.fetchTileImage(for: coord) != nil else { continue }
                    cnt += 1
                }
            }
        }
        #expect(cnt == total)

        let sp2 = builder2.makePreview()
        #expect(sp2.fetchMacroJPEGImage() != nil)
    }
}
