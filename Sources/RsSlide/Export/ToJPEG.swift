import Foundation
import LibJPEGTurbo

extension Slide {
    func crop(rect: CGRect, toJPEG url: URL) throws {
        let roiWidth = UInt16(rect.width)
        let roiHeight = UInt16(rect.height)
        guard roiWidth < UInt16.max && roiHeight < UInt16.max else {
            throw SlideExportError.imageTooLargeForJPEG(
                width: layerImageSize.last?.w, height: layerImageSize.last?.h)
        }

        let colMin = Int(floor(rect.minX / CGFloat(tileTrait.size.w)))
        let rowMin = Int(floor(rect.minY / CGFloat(tileTrait.size.h)))
        let colMax = Int(floor(rect.maxX / CGFloat(tileTrait.size.w)))
        let rowMax = Int(floor(rect.maxY / CGFloat(tileTrait.size.h)))
        let tileFrom = TileCoordinate(layer: 0, row: rowMin, col: colMin)
        let tileTo = TileCoordinate(layer: 0, row: rowMax, col: colMax)
        guard let pxdata = fetchPixelData(from: tileFrom, to: tileTo) else {
            throw SlideExportError.insufficientMemoryForPixelData
        }

        let offsetX = Int(rect.minX) - colMin * tileTrait.size.w
        let offsetY = Int(rect.minY) - rowMin * tileTrait.size.h
        let offset = offsetY * pxdata.pitch + offsetX * tileTrait.pixelBytes

        try pxdata.pixels.withUnsafeBytes { buf in
            let tj = tj3Init(Int32(TJINIT_COMPRESS.rawValue))
            defer { tj3Destroy(tj) }
            tj3Set(tj, Int32(TJPARAM_QUALITY.rawValue), Int32(85))
            tj3Set(tj, Int32(TJPARAM_SUBSAMP.rawValue), TJSAMP_420.rawValue)
            tj3Set(tj, Int32(TJPARAM_XDENSITY.rawValue), Int32(300))
            tj3Set(tj, Int32(TJPARAM_YDENSITY.rawValue), Int32(300))
            tj3Set(tj, Int32(TJPARAM_DENSITYUNITS.rawValue), Int32(1))  // 1=inch

            var jpegBuf: UnsafeMutablePointer<UInt8>?
            defer { tj3Free(jpegBuf) }
            var jpegSize: Int = 0

            if let baseAddress = buf.baseAddress,
                tj3Compress8(
                    tj, baseAddress + offset,
                    Int32(rect.width), Int32(pxdata.pitch), Int32(rect.height),
                    tileTrait.tjPF.rawValue, &jpegBuf, &jpegSize) == 0,
                let jpegBuf, jpegSize > 0
            {
                try Data(bytesNoCopy: jpegBuf, count: jpegSize, deallocator: .none).write(to: url)
            } else {
                throw SlideExportError.insufficientMemoryForJPEG
            }
        }
    }
}
