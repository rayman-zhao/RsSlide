import Foundation
import LibJPEGTurbo
import LibTIFF
import RsSlide
import Testing

@Suite
struct SlidePreviewTests {
    init() async {
        await TIFFSetWarningHandler { _, _ in }
    }

    @Test(
        .serialized,
        arguments: [
            ("SVS/B20028048-1.svs", false),
            ("SVS/125870-2022;1C_20220926112546.svs", false),
            ("SVS/2312399.svs", false),
            ("KFB/1021754 (2).tif", false),
            ("MDS/6横纹肌肉瘤/", true),
            ("MDS/19.1_20160414_1904236501_2/1.mds", true),
            ("MDS/114504/1.mds", true),
            ("MDS/0002/1.mds", true),
            ("MDSX/slide.mdsx", true),
            ("MDSX/mdsx_test_enc/1.mdsx", true),
            ("迪英加/L1-4.svs", false),
            ("CSP/sample.csp", false),
            ("OMETIFF/microscope_ometiff.ome.tiff", false),
            ("OMETIFF/Leica-1.ome.tiff", false),
            ("QPTIFF/_20250228132506.qptiff", false),
        ])
    func previewValid(_ fn: String, _ more: Bool) async throws {
        let trait = URL(filePath: fn, relativeTo: BASE).slideKind
        if more && (trait == .genericFile || trait == .genericFolder) {
            return
        }

        print("Previewing \(fn)")
        let sp = evalMakeSlidePreview(fromTrait: trait)
        evalSlidePreviewMacroImage(sp)
    }

    func evalMakeSlidePreview(fromTrait trait: SlideKind) -> SlidePreview {
        guard case .slide(let builder) = trait else { fatalError() }

        let st = Date()
        let sp = builder.makePreview()
        let et = Date()
        print("Open consumed \(et.timeIntervalSince(st) * 1000) ms")
        return sp
    }

    func evalSlidePreviewMacroImage(_ sp: SlidePreview) {
        let st = Date()
        let img = Data(sp.fetchMacroJPEGImage()!)
        let et = Date()
        print("Macro image consumed \(et.timeIntervalSince(st) * 1000) ms")
        #expect(img.isJPEG)
        print("Valid JPEG in \(img.count) bytes")

        try! img.write(
            to: URL(
                filePath: "preview.jpg",
                directoryHint: .notDirectory,
                relativeTo: BASE))

        let (w, h) = tjDecompressHeader([UInt8](img))
        for (degrees, swapsSides) in [(90, true), (180, false), (270, true)] {
            let rotated = sp.fetchMacroJPEGImage(rotationDegrees: degrees)
            #expect(rotated != nil)
            guard let rotated else { continue }
            #expect(Data(rotated).isJPEG)
            let (rw, rh) = tjDecompressHeader(rotated)
            #expect(swapsSides ? (rw, rh) == (h, w) : (rw, rh) == (w, h))

            if degrees == 90 {
                try! Data(rotated).write(
                    to: URL(
                        filePath: "preview_rot90.jpg",
                        directoryHint: .notDirectory,
                        relativeTo: BASE))
            }
        }
        #expect(sp.fetchMacroJPEGImage(rotationDegrees: 45) == nil)
    }
}
