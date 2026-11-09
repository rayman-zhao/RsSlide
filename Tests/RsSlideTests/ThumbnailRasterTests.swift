import Foundation
import RsSlide
import Testing

@Suite
struct ThumbnailRasterTests {
    @Test(
        .serialized,
        arguments: [
            ("SVS/B20028048-1.svs", true),
            ("QPTIFF/_20250228132506.qptiff", false),
        ])
    func rasterValid(_ fn: String, _ isColor: Bool) async throws {
        let trait = URL(filePath: fn, relativeTo: BASE).slideKind
        let s = try #require(evalMakeSlide(fromTrait: trait))

        let st = Date()
        let raster = try #require(s.fetchThumbnailRasterImage(maxSize: 512))
        print(
            "Raster \(raster.width)x\(raster.height) consumed \(Date().timeIntervalSince(st) * 1000) ms"
        )

        #expect(raster.isColor == isColor)
        #expect(raster.width <= 512 && raster.height <= 512)
        #expect(raster.width == 512 || raster.height == 512)
        #expect(
            raster.pixels.count == raster.width * raster.height * (raster.isColor ? 3 : 1))

        // 多通道荧光：每个通道都取得到、与切片格式一致，且与通道 0 同尺寸（合成的前提）
        for channel in 0..<s.channelTrait.count {
            let plane = try #require(s.fetchThumbnailRasterImage(maxSize: 512, channel: channel))
            #expect(plane.isColor == isColor)
            #expect(plane.width == raster.width && plane.height == raster.height)
        }
    }
}
