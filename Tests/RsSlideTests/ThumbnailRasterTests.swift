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
        let raster = try #require(s.fetchThumbnailPixelData(maxSize: 512))
        print(
            "Raster \(raster.width)x\(raster.height) consumed \(Date().timeIntervalSince(st) * 1000) ms"
        )

        // 像素格式由 tileTrait 承载：明场 RGB 交错、荧光逐通道灰度
        #expect(s.tileTrait.pixelFormat == (isColor ? .rgb : .gray))
        // 新契约：原样返回所选层（最小且长边触及 maxSize），缩放与否是消费端的事
        #expect(max(raster.width, raster.height) >= 512)
        // 行距带瓦片网格补齐：≥ 紧排行字节；缓冲按整网格分配，含底缘行补齐
        #expect(raster.pitch >= raster.width * (isColor ? 3 : 1))
        #expect(raster.pixels.count >= raster.pitch * raster.height)

        // 多通道荧光：每个通道都取得到，且与通道 0 同尺寸同行距（合成的前提）
        for channel in 0..<s.channelTrait.count {
            let plane = try #require(s.fetchThumbnailPixelData(maxSize: 512, channel: channel))
            #expect(plane.width == raster.width && plane.height == raster.height)
            #expect(plane.pitch == raster.pitch)
        }
    }
}
