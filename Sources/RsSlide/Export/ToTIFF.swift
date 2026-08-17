import Foundation
import LibTIFF
import RsFoundation

extension Slide {
    func crop(rect: CGRect, toTIFF url: URL) throws {
        let roiWidth = Int(ceil(rect.width))
        let roiHeight = Int(ceil(rect.height))
        let stripHeight = tileTrait.size.h
        let pixelBytes = tileTrait.pixelBytes
        let rowStride = roiWidth * pixelBytes

        #if os(Windows)
            let tiff = TIFFOpenW(url.filePath.wideString, "w")
        #else
            let tiff = TIFFOpen(url.filePath, "w")
        #endif
        guard let tiff else { throw SlideExportError.failedToCreateFile(url: url) }
        defer { TIFFClose(tiff) }

        _ = TIFFSetField(tiff, TIFFTAG_IMAGEWIDTH, UInt32(roiWidth))
        _ = TIFFSetField(tiff, TIFFTAG_IMAGELENGTH, UInt32(roiHeight))
        _ = TIFFSetField(tiff, TIFFTAG_BITSPERSAMPLE, UInt16(tileTrait.sampleBits))
        _ = TIFFSetField(tiff, TIFFTAG_SAMPLESPERPIXEL, UInt16(tileTrait.pixelFormat.rawValue))
        _ = TIFFSetField(tiff, TIFFTAG_COMPRESSION, UInt16(COMPRESSION_LZW))
        _ = TIFFSetField(tiff, TIFFTAG_PLANARCONFIG, UInt16(PLANARCONFIG_CONTIG))
        _ = TIFFSetField(tiff, TIFFTAG_ROWSPERSTRIP, UInt32(stripHeight))
        _ = TIFFSetField(tiff, TIFFTAG_RESOLUTIONUNIT, UInt16(RESUNIT_CENTIMETER))
        _ = TIFFSetField(tiff, TIFFTAG_XRESOLUTION, Float(1.0 / scanScale * 1000 * 10))
        _ = TIFFSetField(tiff, TIFFTAG_YRESOLUTION, Float(1.0 / scanScale * 1000 * 10))

        switch tileTrait.pixelFormat {
        case .rgb:
            _ = TIFFSetField(tiff, TIFFTAG_PHOTOMETRIC, UInt16(PHOTOMETRIC_RGB))
        case .gray:
            _ = TIFFSetField(tiff, TIFFTAG_PHOTOMETRIC, UInt16(PHOTOMETRIC_MINISBLACK))
        }

        let stripCount = Int(ceil(Double(roiHeight) / Double(stripHeight)))

        for stripIndex in 0..<stripCount {
            let stripTop = stripIndex * stripHeight
            let stripHeightActual = min(stripHeight, roiHeight - stripTop)
            let stripRectY = Int(rect.minY) + stripTop
            let stripRectX = Int(rect.minX)
            let stripRectH = stripHeightActual
            let stripRectW = roiWidth

            let tileOriginX =
                Int(floor(CGFloat(stripRectX) / CGFloat(tileTrait.size.w)))
                * tileTrait.size.w
            let tileOriginY =
                Int(floor(CGFloat(stripRectY) / CGFloat(tileTrait.size.h)))
                * tileTrait.size.h

            let colMin = Int(floor(CGFloat(stripRectX) / CGFloat(tileTrait.size.w)))
            let rowMin = Int(floor(CGFloat(stripRectY) / CGFloat(tileTrait.size.h)))
            let colMax = Int(
                floor((CGFloat(stripRectX + stripRectW) - 1.0) / CGFloat(tileTrait.size.w)))
            let rowMax = Int(
                floor((CGFloat(stripRectY + stripRectH) - 1.0) / CGFloat(tileTrait.size.h)))

            let tileFrom = TileCoordinate(layer: 0, row: rowMin, col: colMin)
            let tileTo = TileCoordinate(layer: 0, row: rowMax, col: colMax)
            guard let pxdata = fetchPixelData(from: tileFrom, to: tileTo) else {
                throw SlideExportError.insufficientMemoryForPixelData
            }

            let localX = stripRectX - tileOriginX
            let localY = stripRectY - tileOriginY
            let localRight = stripRectX + stripRectW - tileOriginX
            let localBottom = stripRectY + stripRectH - tileOriginY

            let startX = max(0, localX)
            let startY = max(0, localY)
            let endX = min(pxdata.width, localRight)
            let endY = min(pxdata.height, localBottom)
            let bufferHeight = max(0, endY - startY)
            let leftPad = max(0, -localX)
            let topPad = max(0, -localY)
            let stripBytes = rowStride * stripHeightActual
            var stripPixels = [UInt8](repeating: 0, count: stripBytes)

            for y in startY..<endY {
                let srcRowOffset = y * pxdata.pitch + startX * pixelBytes
                let dstRowOffset = (y - startY + topPad) * rowStride + leftPad * pixelBytes
                let copyWidth = max(0, endX - startX)
                guard copyWidth > 0 else { continue }

                pxdata.pixels.withUnsafeBytes { srcBuf in
                    guard let srcBase = srcBuf.baseAddress else { return }
                    memcpy(
                        &stripPixels[dstRowOffset], srcBase + srcRowOffset, copyWidth * pixelBytes)
                }
            }

            let writeResult = stripPixels.withUnsafeBytes { srcBuf in
                guard let srcBase = srcBuf.baseAddress else { return tmsize_t(-1) }
                return TIFFWriteEncodedStrip(
                    tiff,
                    UInt32(stripIndex),
                    UnsafeMutableRawPointer(mutating: srcBase),
                    tmsize_t(bufferHeight * rowStride)
                )
            }

            guard writeResult >= 0 else {
                throw SlideExportError.failedToWriteFile
            }
        }

        guard TIFFWriteDirectory(tiff) == 1 else {
            throw SlideExportError.failedToWriteFile
        }
    }
}
