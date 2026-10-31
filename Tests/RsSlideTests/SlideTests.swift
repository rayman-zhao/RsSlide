import Foundation
import FoundationXML
import LibJPEGTurbo
import LibTIFF
import Testing

@testable import RsSlide

@Suite
struct SlideTests {
    init() async {
        await TIFFSetWarningHandler { md, msg in
            // print("TIFFWarning: \(md) - \(msg)")
        }
    }

    @Test(
        .serialized,
        arguments: [
            (
                "CSP/空军北部战区医院.csp", "EBA41EAB-6803-5CBA-BD60-05489761CECF",
                "空军北部战区医院",
                "CSP", true, true, false, false
            ),
            (
                "SVS/B20028048-1.svs", "C5A15CA7-6151-5520-B25A-212D441C30D5",
                "B20028048-1",
                "SVS", true, true, false, false
            ),
            (
                "志盈/60637.svs", "8495DB07-A11A-55C5-B606-AAFAB29BF4D6",
                "60637",
                "SVS", true, true, false, false
            ),
            (
                "SVS/125870-2022;1C_20220926112546.svs", "33D0CE0D-3A5F-55B6-BF87-F47841EE52A5",
                "125870-2022;1C_20220926112546",
                "SVS", true, true, false, false
            ),
            (
                "SVS/2312399.svs", "9F23270E-E03B-5F9D-9D85-136835176D09",
                "2312399",
                "SVS", false, true, false, false
            ),
            (
                "KFB/1021754 (2).tif", "EFD73D09-4D58-517D-8E50-D59FDA53F7A0",
                "1021754 (2)",
                "TIF", true, true, false, false
            ),
            (
                "MDS/6横纹肌肉瘤/", "D1C530A6-EE7F-47BD-B2E6-766EC973742D",
                "6横纹肌肉瘤",
                "MDS", false, false, true, false
            ),
            (
                "MDS/7多形性脂肪肉瘤/1.mds", "A7D41B1D-0B0F-49AB-83DE-DA25ADE91231",
                "7多形性脂肪肉瘤",
                "MDS", false, false, true, false
            ),
            (
                "MDS/19.1_20160414_1904236501_2/1.mds", "6adb43b1-49bb-4992-8a30-5eef1352dc9e",
                "19.1_20160414_1904236501_2",
                "MDS", true, true, true, false
            ),
            (
                "MDS/114504/", "509f235d-099a-40aa-a56f-eb96d82ae372",
                "114504",
                "MDS", false, false, true, false
            ),
            (
                "MDS/0002/", "A159D05B-ADE7-4FBA-B344-DA6E1BE33102",
                "0002",
                "MDS", false, true, true, false
            ),
            (
                "MDS/BW20200014/", "7A25F880-7BC2-44BA-8362-8E82EC70A6BF",
                "BW20200014",
                "MDS", true, true, true, false
            ),
            (
                "MDSX/4/", "7C759554-512B-452C-A7DD-B512883B6602",
                "4",
                "MDSX", false, true, true, false
            ),
            (
                "MDSX/slide.mdsx", "81be8ba7-b0be-4f96-81be-014ece99e581",
                "slide",
                "MDSX", true, true, true, false
            ),
            (
                "MDSX/mdsx_test_enc/1.mdsx", "7B517EA2-2601-4279-A2B9-30E1415E5935",
                "mdsx_test_enc",
                "MDSX", true, true, true, false
            ),
            (
                "迪英加/L1-4.svs", "0A508412-C06C-5A09-BED2-DAC5F736B9D7",
                "L1-4",
                "SVS", true, true, false, false
            ),
            (
                "SVS/201203757.svs", "4090FE56-7C14-569F-B8F0-DDEFB0D68A9D",
                "201203757",
                "SVS", true, false, false, false
            ),
            (
                "CSP/WC.csp", "151A7101-2885-5B72-8138-F59051F9039B",
                "WC",
                "CSP", true, true, false, false
            ),
            (
                "SVS/icc.svs", "2A8FA2CA-4B4C-501F-8AE1-1C2570D5BFC9",
                "icc",
                "SVS", true, true, false, false
            ),
            (
                "秉理/G202601407AFP.svs", "7447E452-43A5-51E5-962A-0C11737CDDB5",
                "G202601407AFP",
                "SVS", true, true, false, false
            ),
            (
                "OMETIFF/microscope_ometiff.ome.tiff", "2c66263d-9b63-40a1-a11e-ebb787305fb9",
                "microscope_ometiff",
                "OME.TIFF", true, true, false, false
            ),
            (
                "OMETIFF/Leica-1.ome.tiff", "db30c0bc-b59a-425e-9e2c-bf9bb1dc2cb5",
                "Leica-1",
                "OME.TIFF", false, true, false, false
            ),
            (
                "260808-6.tif", "db30c0bc-b59a-425e-9e2c-bf9bb1dc2cb5",
                "260808-6",  // Stripped TIF, init nil.
                "TIF", false, false, false, true
            ),
            (
                "DCM/锦州582531-10/", "78d041ac-3756-51d4-9c8b-224e846cabdb",
                "锦州582531-10",
                "DCM", true, true, false, false
            ),
            (
                "奥林巴斯/图像.vsi", "BAED0ED8-446F-5205-9434-2F13A934F1CF",
                "图像",
                "VSI", true, true, false, false
            ),
            (
                "奥林巴斯/图像_王磊-PD-L1.vsi", "3BB99B98-572A-5805-A359-5C3DEA00DAD3",
                "图像_王磊-PD-L1",
                "VSI", true, true, false, false
            ),
        ])
    func slideValid(
        _ fn: String, _ sid: String, _ name: String, _ fmt: String,
        _ label: Bool, _ macro: Bool, _ more: Bool, _ failedInit: Bool
    ) async throws {
        let trait = URL(filePath: fn, relativeTo: BASE).slideKind
        if more && (trait == .genericFile || trait == .genericFolder) {
            return
        }

        print("Validating \(fn)")
        if failedInit {
            #expect(evalMakeSlide(fromTrait: trait) == nil)
            return
        }

        let s = try #require(evalMakeSlide(fromTrait: trait))
        #expect(s.id == UUID(uuidString: sid))
        #expect(s.name == name)
        #expect(s.format == fmt)
        await evalSlideMetadata(s)
        #expect(throws: Never.self) {
            if label {
                try evalSlideLabelImage(s)
            } else {
                #expect(s.fetchLabelJPEGImage() == nil)
            }
            if macro {
                try evalSlideMacroImage(s)
            } else {
                #expect(s.fetchMacroJPEGImage() == nil)
            }
            try evalSlideThumbnailImage(s)
        }
    }

    @Test(
        .serialized,
        arguments: [
            // "3D Histech/Cell.tif",
            // "QPTIFF/23SC-5-2.qptiff",
            // "QPTIFF/02914056_20230103124040.qptiff",
            // "QPTIFF/02914056_20230103131001.qptiff",
            // "QPTIFF/derm-FITC_20231005163648.qptiff",
            // "QPTIFF/胰岛-绿橙红-01-EDF.qptiff",
            // "QPTIFF/bmp-qptiff.qptiff",
            // "QPTIFF/20260513152446-24.qptiff",
            // "QPTIFF/202404171225-3fl.qptiff",
            // "QPTIFF/20240417-4FL.qptiff",
            // "QPTIFF/_20250228132506.qptiff",
            // "MDSX/PV183/1.mdsx",
            // "DCM/锦州582531-10/",
            "奥林巴斯/图像.vsi",
            "奥林巴斯/图像_王磊-PD-L1.vsi",
        ])
    func slideTileValid(_ fn: String) async throws {
        let trait = URL(filePath: fn, relativeTo: BASE).slideKind
        print("Validating \(fn)")
        let s = try #require(evalMakeSlide(fromTrait: trait))

        #expect(evalSequenceTiles(s) == evalRandomTiles(s))
        try evalVirtualTiles(s)
    }
}
