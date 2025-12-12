import Foundation
import Testing
import LibTIFF
import RsSlide

@Suite
struct SlidePreviewTests {
   init() async {
       await TIFFSetWarningHanlder { _, _ in }
   }

    @Test(.serialized, arguments: [
        ("SVS/125870-2022;1C_20220926112546.svs", false),
        ("SVS/2312399.svs", false),
        ("KFB/1021754 (2).tif", false),
        ("MDS/6横纹肌肉瘤/", true),
        ("MDS/19.1_20160414_1904236501_2/1.mds", true),
        ("MDS/114504/1.mds", true),
        ("MDS/0002/1.mds", true),
    ])
    func previewValid(_ fn: String, _ more: Bool) async throws {
        let trait = URL(filePath: fn, relativeTo: BASE).slideTrait
        if more && (trait == .isGenericFile || trait == .isGenericFolder) {
            return
        }

        print("Previewing \(fn)")
        let sp = evalMakeSlidePreview(fromTrait: trait)
        evalSlidePreviewMacroImage(sp)
    }

    func evalMakeSlidePreview(fromTrait trait: SlideTrait) -> SlidePreview {
        guard case .isSlide(let builder) = trait else { fatalError() }

        let st = Date()
        let sp = builder.makePreview()
        let et = Date()
        print("Open consumed \(et.timeIntervalSince(st) * 1000) ms")
        return sp
    }

    func evalSlidePreviewMacroImage(_ sp: SlidePreview) {
        let st = Date()
        let img = sp.fetchMacroJPEGImage() as Data
        let et = Date()
        print("Macro image consumed \(et.timeIntervalSince(st) * 1000) ms")
        #expect(img.isJPEG)
        print("Valid JPEG in \(img.count) bytes")
    }
}