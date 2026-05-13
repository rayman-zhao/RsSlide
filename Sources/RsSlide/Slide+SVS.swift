import Foundation
import LibTIFF
import LibJPEGTurbo
import RsHelper

extension Slide {
    func saveAsSVS(to url: URL) throws {
    #if os(Windows)
        let tiff = TIFFOpenW(url.filePath.wideString, "w")
    #else
        let tiff = TIFFOpen(url.filePath, "w")
    #endif
        guard let tiff else { throw SlideExportError.failedCreateSVSFile(url: url) }
        defer {
            TIFFClose(tiff)
        }

        let tileWidth = UInt32(tileTrait.size.w)
        let tileHeight = UInt32(tileTrait.size.h)
        let res = Float(1.0 / scanScale * 1000 * 10);
        for layer in layerImageSize.enumerated() {
            let index = layer.offset
            let width = layer.element.w
            let height = layer.element.h
            let cols = layerTileSize[layer.offset].c
            let rows = layerTileSize[layer.offset].r
            log.debug("Exporting layer \(layer.offset) with size \(width)x\(height) and tile size \(cols)x\(rows)")

            if index == 0 {
                let desc = """
                    Aperio
                    \(width)x\(height)[0, 0 \(width)x\(height)](\(tileWidth)x\(tileHeight)) JPEG / RGB Q = 75 | AppMag = \(scanObjective) | MPP = \(scanScale)
                    """
                desc.withCString { ptr in
                    _ = TIFFSetField(tiff, TIFFTAG_IMAGEDESCRIPTION, ptr)
                }
            } else {
                _ = TIFFSetField(tiff, TIFFTAG_SUBFILETYPE, UInt32(FILETYPE_REDUCEDIMAGE));
            }

            _ = TIFFSetField(tiff, TIFFTAG_IMAGEWIDTH, UInt32(width))
            _ = TIFFSetField(tiff, TIFFTAG_IMAGELENGTH, UInt32(height))
            _ = TIFFSetField(tiff, TIFFTAG_BITSPERSAMPLE, UInt16(tileTrait.sampleBits))
            _ = TIFFSetField(tiff, TIFFTAG_SAMPLESPERPIXEL, UInt16(tileTrait.pixelFormat.rawValue))
            _ = TIFFSetField(tiff, TIFFTAG_XRESOLUTION, res)
            _ = TIFFSetField(tiff, TIFFTAG_YRESOLUTION, res)
            _ = TIFFSetField(tiff, TIFFTAG_PLANARCONFIG, UInt16(PLANARCONFIG_CONTIG))
            _ = TIFFSetField(tiff, TIFFTAG_RESOLUTIONUNIT, UInt16(RESUNIT_CENTIMETER))
            _ = TIFFSetField(tiff, TIFFTAG_TILEWIDTH, UInt32(tileWidth))
            _ = TIFFSetField(tiff, TIFFTAG_TILELENGTH, UInt32(tileHeight))
            _ = TIFFSetField(tiff, TIFFTAG_COMPRESSION, UInt16(COMPRESSION_JPEG))
                //TIFFSetField(tiff, TIFFTAG_JPEGQUALITY, 75);

            var firstTile = true
            for row in 0..<rows {
                for col in 0..<cols {
                    let coord = TileCoordinate(layer: index, row: row, col: col)
                    guard var tileRawImage = fetchTileRawImage(at: coord) else { continue }

                    if firstTile {
                        firstTile = false

                        let tj = tj3Init(Int32(TJINIT_DECOMPRESS.rawValue))
                        defer { tj3Destroy(tj) }

                        if tj3DecompressHeader(tj, tileRawImage, tileRawImage.count) == 0 {
                            _ = tiffSetPhotometric(tiff, tj3Get(tj, TJPARAM_COLORSPACE.rawValue))
                            _ = tiffSetSubsampling(tiff, tj3Get(tj, TJPARAM_SUBSAMP.rawValue))
                        }
                    }

                    let tileId = TIFFComputeTile(tiff, UInt32(col) * tileWidth, UInt32(row) * tileHeight, 0, 0)
                    _ = tileRawImage.withUnsafeMutableBytes { ptr in
                        TIFFWriteRawTile(tiff, tileId, ptr.baseAddress, Int64(ptr.count))
                    }
                }
            }
            guard TIFFWriteDirectory(tiff) == 1 else { throw SlideExportError.failedWriteSVSDirectory }

            if index == 0 {
                try writeImageDirectory(tiff, fetchThumbnailJPEGImage())
            }
        }
        try writeImageDirectory(tiff, fetchLabelJPEGImage(), "Aperio\nlabel")
        try writeImageDirectory(tiff, fetchMacroJPEGImage(), "Aperio\nmacro")
    }

    private func writeImageDirectory(_ tiff: OpaquePointer, _ jpeg: [UInt8]?, _ name: String? = nil) throws {
        guard var jpeg = jpeg else {
            log.info("No JPEG image to write for description: \(name ?? "thumbnail")")
            return
        }

        let tj = tj3Init(Int32(TJINIT_DECOMPRESS.rawValue))
        defer { tj3Destroy(tj) }

        if tj3DecompressHeader(tj, jpeg, jpeg.count) == 0 {
            let width = UInt32(tj3Get(tj, TJPARAM_JPEGWIDTH.rawValue))
            let height = UInt32(tj3Get(tj, TJPARAM_JPEGHEIGHT.rawValue))

            _ = TIFFSetField(tiff, TIFFTAG_IMAGEWIDTH, width);
            _ = TIFFSetField(tiff, TIFFTAG_IMAGELENGTH, height);
            _ = TIFFSetField(tiff, TIFFTAG_ROWSPERSTRIP, height);

            if let name {
                let desc = "\(name) \(width)x\(height)"
                desc.withCString { ptr in
                    _ = TIFFSetField(tiff, TIFFTAG_IMAGEDESCRIPTION, ptr)
                }
            }

            _ = TIFFSetField(tiff, TIFFTAG_BITSPERSAMPLE, UInt16(8));
            _ = TIFFSetField(tiff, TIFFTAG_SAMPLESPERPIXEL, UInt16(3));
            _ = TIFFSetField(tiff, TIFFTAG_PLANARCONFIG, UInt16(PLANARCONFIG_CONTIG));
            _ = TIFFSetField(tiff, TIFFTAG_COMPRESSION, UInt16(COMPRESSION_JPEG));
            _ = tiffSetPhotometric(tiff, tj3Get(tj, TJPARAM_COLORSPACE.rawValue))
            _ = tiffSetSubsampling(tiff, tj3Get(tj, TJPARAM_SUBSAMP.rawValue))
        }

        _ = jpeg.withUnsafeMutableBytes { ptr in
            TIFFWriteRawStrip(tiff, 0, ptr.baseAddress, Int64(ptr.count))
        }
        guard TIFFWriteDirectory(tiff) == 1 else { throw SlideExportError.failedWriteSVSDirectory }
    }

    private func tiffSetPhotometric(_ tiff: OpaquePointer, _ tjcs: Int32) -> Bool {
        switch tjcs {
        case TJCS_RGB.rawValue:
            return TIFFSetField(tiff, TIFFTAG_PHOTOMETRIC, UInt16(PHOTOMETRIC_RGB))
        case TJCS_YCbCr.rawValue:
            return TIFFSetField(tiff, TIFFTAG_PHOTOMETRIC, UInt16(PHOTOMETRIC_YCBCR))
        case TJCS_GRAY.rawValue:
            return TIFFSetField(tiff, TIFFTAG_PHOTOMETRIC, UInt16(PHOTOMETRIC_MINISBLACK))
        default:
            log.error("Unsupported JPEG colorspace \(tjcs).")
            return false
        }
    }

    private func tiffSetSubsampling(_ tiff: OpaquePointer, _ tjsubsamp: Int32) -> Bool {
        switch tjsubsamp {
        case TJSAMP_444.rawValue:
            return TIFFSetField(tiff, TIFFTAG_YCBCRSUBSAMPLING, UInt16(1), UInt16(1))
        case TJSAMP_422.rawValue:
            return TIFFSetField(tiff, TIFFTAG_YCBCRSUBSAMPLING, UInt16(2), UInt16(1))
        case TJSAMP_420.rawValue:
            return TIFFSetField(tiff, TIFFTAG_YCBCRSUBSAMPLING, UInt16(2), UInt16(2))
        case TJSAMP_440.rawValue:
            return TIFFSetField(tiff, TIFFTAG_YCBCRSUBSAMPLING, UInt16(1), UInt16(2))
        case TJSAMP_411.rawValue:
            return TIFFSetField(tiff, TIFFTAG_YCBCRSUBSAMPLING, UInt16(4), UInt16(1))
        default:
            log.error("Unsupported JPEG subsampling \(tjsubsamp).")
            return false
        }
    }
}
