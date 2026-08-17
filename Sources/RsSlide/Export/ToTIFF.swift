import Foundation
import LibTIFF
import RsFoundation

extension Slide {
    func crop(rect: CGRect, toTIFF url: URL) throws {
        #if os(Windows)
            let tiff = TIFFOpenW(url.filePath.wideString, "w")
        #else
            let tiff = TIFFOpen(url.filePath, "w")
        #endif
        guard let tiff else { throw SlideExportError.failedToCreateFile(url: url) }
        defer { TIFFClose(tiff) }

        let stripHeight = tileTrait.size.h

        _ = TIFFSetField(tiff, TIFFTAG_IMAGEWIDTH, UInt32(rect.width))
        _ = TIFFSetField(tiff, TIFFTAG_IMAGELENGTH, UInt32(rect.height))
        _ = TIFFSetField(tiff, TIFFTAG_BITSPERSAMPLE, UInt16(tileTrait.sampleBits))
        _ = TIFFSetField(tiff, TIFFTAG_SAMPLESPERPIXEL, UInt16(tileTrait.pixelFormat.rawValue))
        _ = TIFFSetField(tiff, TIFFTAG_COMPRESSION, UInt16(COMPRESSION_LZW))
        _ = TIFFSetField(tiff, TIFFTAG_PLANARCONFIG, UInt16(PLANARCONFIG_CONTIG))
        _ = TIFFSetField(tiff, TIFFTAG_ROWSPERSTRIP, UInt32(stripHeight))
        _ = TIFFSetField(tiff, TIFFTAG_RESOLUTIONUNIT, UInt16(RESUNIT_INCH))
        _ = TIFFSetField(tiff, TIFFTAG_XRESOLUTION, Float(1.0 / scanScale * 1000 * 25.4))
        _ = TIFFSetField(tiff, TIFFTAG_YRESOLUTION, Float(1.0 / scanScale * 1000 * 25.4))

        switch tileTrait.pixelFormat {
        case .rgb:
            _ = TIFFSetField(tiff, TIFFTAG_PHOTOMETRIC, UInt16(PHOTOMETRIC_RGB))
        case .gray:
            _ = TIFFSetField(tiff, TIFFTAG_PHOTOMETRIC, UInt16(PHOTOMETRIC_MINISBLACK))
        }

        // Init with first tile row
        let encodingPitch = Int(rect.width) * tileTrait.pixelBytes
        var encodingPixels = [UInt8](repeating: 0, count: stripHeight * encodingPitch)

        let colMin = Int(floor(rect.minX / CGFloat(tileTrait.size.w)))
        let colMax = Int(floor(rect.maxX / CGFloat(tileTrait.size.w)))
        let rowMin = Int(floor(rect.minY / CGFloat(tileTrait.size.h)))

        var pendingPixels: [UInt8] = []
        let pendingX = colMin * tileTrait.size.w
        let pendingWidth = (colMax - colMin + 1) * tileTrait.size.w
        let pendingPitch = pendingWidth * tileTrait.pixelBytes
        var pendingHeight = 0

        let offsetXBytes = (Int(rect.minX) - pendingX) * tileTrait.pixelBytes
        var offsetY = Int(rect.minY) - (rowMin * tileTrait.size.h)

        let rowMax = Int(floor(rect.maxY / CGFloat(tileTrait.size.h)))
        var stripNumber = UInt32(0)
        for row in rowMin...rowMax {
            let tileFrom = TileCoordinate(layer: 0, row: row, col: colMin)
            let tileTo = TileCoordinate(layer: 0, row: row, col: colMax)
            guard let pxdata = fetchPixelData(from: tileFrom, to: tileTo) else {
                throw SlideExportError.insufficientMemoryForPixelData
            }

            pendingPixels.append(contentsOf: pxdata.pixels)
            pendingHeight += pxdata.height
            if offsetY > 0 {
                pendingPixels.removeFirst(offsetY * pendingPitch)
                pendingHeight -= offsetY
                offsetY = 0
            }

            while pendingHeight > 0 && (pendingHeight >= stripHeight || row == rowMax) {
                let stripHeightActual = min(stripHeight, pendingHeight)

                for y in 0..<stripHeightActual {
                    let dest = y * encodingPitch
                    let src = y * pendingPitch + offsetXBytes
                    encodingPixels.replaceSubrange(
                        dest..<(dest + encodingPitch),
                        with: pendingPixels[src..<(src + encodingPitch)])
                }

                try encodingPixels.withUnsafeBytes { buf in
                    if let baseAddress = buf.baseAddress,
                        TIFFWriteEncodedStrip(
                            tiff, UInt32(stripNumber),
                            UnsafeMutableRawPointer(mutating: baseAddress),
                            tmsize_t(stripHeightActual * encodingPitch)
                        ) > 0
                    {
                        stripNumber += 1
                    } else {
                        throw SlideExportError.failedToWriteFile
                    }
                }

                pendingPixels.removeFirst(stripHeightActual * pendingPitch)
                pendingHeight -= stripHeightActual
            }
        }

        guard TIFFWriteDirectory(tiff) == 1 else {
            throw SlideExportError.failedToWriteFile
        }
    }
}
