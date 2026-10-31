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
