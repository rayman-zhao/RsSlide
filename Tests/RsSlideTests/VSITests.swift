import Foundation
import Testing
@testable import RsSlide

@Suite
struct VSITests {
    @Test(arguments: [
        "奥林巴斯/图像.vsi",
        "奥林巴斯/图像_王磊-PD-L1.vsi",
    ])
    func metadataTree(_ fn: String) throws {
        let data = try Data(contentsOf: URL(filePath: fn, relativeTo: BASE))
        let meta = try #require(VSIMetadata(data: data))
        print("=== \(fn)")

        let collection = try #require(meta.root.first { $0.tag == 2000 })
        let images = collection.children.filter { $0.tag == 2001 }
        #expect(images.count >= 3)

        var mainScans = 0
        for image in images {
            guard let props = image.first(2005) else { continue }
            let name = props.text(2030)
            let type = props.ints(2074)?.first
            let mpp = props.doubles(2019)?.first

            var size = (w: 0, h: 0)
            var external = false
            for frame in image.children where frame.tag == 2002 {
                guard let file = frame.first(2018) else { continue }
                if let boundary = file.ints(2053), boundary.count == 4 {
                    size = (boundary[2], boundary[3])
                }
                if file.ints(20005)?.first == 1 { external = true }
            }
            if type == 0 && external { mainScans += 1 }

            let magnification = firstValue(image, tag: 1073741824)
            print(
                "image id=\(image.secondTag ?? -1) name=\(name ?? "?") type=\(type ?? -1) \(size.w)x\(size.h) mpp=\(mpp ?? -1) mag=\(magnification ?? 0) external=\(external)"
            )
        }
        #expect(mainScans >= 1)
    }

    @Test(arguments: [
        "奥林巴斯/图像.vsi",
        "奥林巴斯/图像_王磊-PD-L1.vsi",
    ])
    func slideOpen(_ fn: String) throws {
        let s = try #require(VSI(path: URL(filePath: fn, relativeTo: BASE)))
        print(
            "\(fn) id=\(s.id.uuidString) layers=\(s.layerImageSize.count) \(s.layerImageSize[0]) tiles=\(s.layerTileSize[0]) zoom=\(s.layerZoom) objective=\(s.scanObjective) scale=\(s.scanScale)"
        )
        #expect(s.layerImageSize[0].w > 10000)
        #expect(s.scanObjective == 40 || s.scanObjective == 20)
        #expect(s.scanScale > 0.1 && s.scanScale < 0.5)
        #expect(s.tileTrait.backgroundColorRGB <= 0xFFFFFF)
    }

    /// FileHandle seek/read beyond 2 GiB (large `.ets` stacks exceed it),
    /// pinned against `od` ground truth from a 3.37 GiB QPTIFF slide.
    @Test func fileHandleBeyond2GiB() throws {
        let url = URL(filePath: "QPTIFF/_20250228132506.qptiff", relativeTo: BASE)
        let handle = try #require(try? FileHandle(forReadingFrom: url))

        let probes: [(UInt64, [UInt8])] = [
            (
                2_500_000_000,
                [0x24, 0xda, 0x24, 0x74, 0x92, 0x0c, 0xb6, 0xff, 0x64, 0x40, 0x5b, 0x09,
                    0x1a, 0xcb, 0x63, 0x3c, 0x27, 0x83, 0x90, 0xc2, 0xe8, 0x02, 0x39, 0x64,
                    0x64, 0xe2, 0x04, 0x9a, 0xc2, 0xa5, 0x5c, 0x2b]
            ),
            (
                3_000_000_000,
                [0x9b, 0xcf, 0x26, 0xc3, 0xc7, 0xab, 0xa9, 0xcb, 0xa2, 0xe1, 0x92, 0x17,
                    0x63, 0x18, 0xa9, 0xb9, 0xea, 0x99, 0x59, 0xe4, 0x80, 0x13, 0x09, 0x07,
                    0xcb, 0x96, 0x00, 0x30, 0x05, 0x87, 0xe0, 0x79]
            ),
            (
                3_366_203_264,
                [0xac, 0x2e, 0x4d, 0xa6, 0x06, 0x37, 0xa8, 0x47, 0xc2, 0xc6, 0xec, 0xf7,
                    0x8d, 0x72, 0x8a, 0x4e, 0x96, 0xee, 0x87, 0xa4, 0xa9, 0x4f, 0x8b, 0xab,
                    0x69, 0xd0, 0x01, 0x42, 0x21, 0x5d, 0x5c, 0x51]
            ),
        ]

        for (offset, want) in probes {
            try handle.seek(toOffset: offset)
            let data = try #require(try? handle.read(upToCount: want.count))
            #expect([UInt8](data) == want)
        }
    }

    private func firstValue(_ node: VSIMetadata.Node, tag: Int) -> Double? {
        if node.tag == tag {
            if let d = node.doubles { return d[0] }
            if let i = node.ints { return Double(i[0]) }
        }
        for child in node.children {
            if let v = firstValue(child, tag: tag) { return v }
        }
        return nil
    }
}
