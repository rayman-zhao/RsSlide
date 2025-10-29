import Foundation
import LibTIFF
import LibJPEGTurbo
import RsHelper

struct SVSPreview : SlidePreview {
    let path: URL
    
    func fetchMacroJPEGImage() -> Data {
    #if os(Windows)
        let tiff = TIFFOpenW(path.path.utf16 + [0], "rh")
    #else
        let tiff = TIFFOpen(path.path, "rh")
    #endif
        guard tiff != nil else { return Data() }
        defer {
            TIFFClose(tiff)
        }
        
        return TIFFReadJPEGImage(tiff, TIFFNumberOfDirectories(tiff) - 1)
    }
}

final class SVS : Slide {
    let tiff: OpaquePointer?
    var layerDir: [UInt32] = []
    var macroDir: UInt32 = 0
    var labelDir: UInt32 = 0
    var imageDesc = ""
    
    var id: UUID {
        get {
            let fingerprint = """
            dataSize: \(dataSize)
            imageDesc: \(imageDesc)
            layers: \(layerImageSize)
            """

            return Data(fingerprint.utf8).hashUUID
        }
    }
    var dataSize: Int = -1
    var scanObjective = 0
    var scanScale = 0.0
    let tierCount: Int = 1
    var tileTrait: TileTrait = TileTrait(width: 0, height: 0)
    var layerZoom = 0
    var layerImageSize: [(w: Int, h: Int)] = []
    var layerTileSize: [(r: Int, c: Int)] = []
    
    init?(path: URL) {
    #if os(Windows)
        tiff = TIFFOpenW(path.path.utf16 + [0], "rh")
    #else
        tiff = TIFFOpen(path.path, "rh") // h - Read TIFF header only, do not load the first directory.
    #endif
        guard tiff != nil else { return nil }
        
        dataSize = path.fileSize
        
        importDirectories()
        
        if layerTileSize.count > 1 {
            // The 2312399.svs has 4.00036166 zoom, so that use tile size instead.
            //layerZoom = Int(ceil(Double(layerImageSize[0].w) / Double(layerImageSize[1].w)))
            layerZoom = Int(ceil(Double(layerTileSize[0].r) / Double(layerTileSize[1].r)))
        }
    }
    
    deinit {
        TIFFClose(tiff)
    }
    
    func fetchLabelJPEGImage() -> Data {
        guard labelDir != 0 else { return Data() }
        return TIFFReadJPEGImage(tiff, labelDir)
    }
    
    func fetchMacroJPEGImage() -> Data {
        guard macroDir != 0 else { return Data() }
        return TIFFReadJPEGImage(tiff, macroDir)
    }
    
    func fetchTileRawImage(at coord: TileCoordinate) -> Data {
        assert(validate(coord: coord))
        guard TIFFSetDirectory(tiff, layerDir[coord.layer]) else { return Data() }
        
        let tid = TIFFComputeTile(tiff, UInt32(coord.col * tileTrait.size.w), UInt32(coord.row * tileTrait.size.h), 0, 0)
        let bufSize = tileTrait.maxBytes
        var buf = [UInt8](repeating: 0, count: bufSize)
        // TODO: var span = buf.mutableSpan
        let tileSize = Int(TIFFReadRawTile(tiff, tid, &buf, tmsize_t(bufSize)))
        guard tileSize > 0 else { return Data()}
        
        return Data(buf[..<tileSize])
    }
    
    private func importDirectories() {
    #if os(macOS)
        let bufSize = 128 * 1024
        var buf = [UInt8](repeating: 0, count: bufSize)
        // TODO: var span = buf.mutableSpan
        let fp = fmemopen(&buf, bufSize, "w")
        defer { fclose(fp) }
    #endif

        while (TIFFReadDirectory(tiff) == 1) {
            let dir = TIFFCurrentDirectory(tiff)
            // KFBio's tif messed up the Subfile Type, have to use tile size to help.
            //let reduced: UInt32? = TIFFGetField(tiff, TIFFTAG_SUBFILETYPE)
            let tw: UInt32? = TIFFGetField(tiff, TIFFTAG_TILEWIDTH)
            
            if dir == 0 && tw != nil { // First directory always be bottom layer image.
                importMetadata(from: dir)
                importLayer(from: dir)
            }
            else if tw != nil { // Sequential reduced layer image.
                importLayer(from: dir)
            }
            else if dir == 1 { // Second non-reduced directory, should be thumbnail image.
                
            }
            else if TIFFLastDirectory(tiff) == 0 { // Second last directory, should be label image.
                labelDir = dir
            }
            else { // Last directory, should be macro image.
                macroDir = dir
            }
            
        #if os(macOS)
            fputs("Directory \(dir)\n", fp)
            TIFFPrintDirectory(tiff, fp, 0)
        #endif
        }
        
    #if os(macOS)
        fflush(fp)
        log.info("\n\(String(decoding: buf, as: UTF8.self))")
    #endif
    }
    
    private func importMetadata(from dir: UInt32) {
        if let tw: UInt32 = TIFFGetField(tiff, TIFFTAG_TILEWIDTH),
           let th: UInt32 = TIFFGetField(tiff, TIFFTAG_TILELENGTH) {
            tileTrait = TileTrait(width: Int(tw), height: Int(th))
        }
        
        if let desc: UnsafeMutablePointer<CChar> = TIFFGetField(tiff, TIFFTAG_IMAGEDESCRIPTION) { // libtiff keep this const char * memory
            imageDesc = String(cString: desc)
            
            let scn = Scanner(string: String(cString: desc))
            
            if scn.scanUpToString("AppMag") != nil,
               scn.scanString("AppMag") != nil,
               scn.scanString("=") != nil,
               let v = scn.scanInt() {
                scanObjective = v
            }
            
            if scn.scanUpToString("MPP") != nil,
               scn.scanString("MPP") != nil,
               scn.scanString("=") != nil,
               let v = scn.scanDouble() {
                scanScale = v
            }
        }
        
        if scanScale == 0.0,
           let res: Float = TIFFGetField(tiff, TIFFTAG_XRESOLUTION),
           let unit: UInt16 = TIFFGetField(tiff, TIFFTAG_RESOLUTIONUNIT) {
            if (unit == RESUNIT_CENTIMETER) {
                scanScale = Double(1 / res * 10 * 1000)
            }
            else if (unit == RESUNIT_INCH) {
                scanScale = Double(1 / res * 25.4 * 1000)
            }
        }
        
        if scanObjective == 0 {
            switch scanScale {
            case 0.15...0.35:
                scanObjective = 40
            case 0.4...0.6:
                scanObjective = 20
            case 0.9...1.1:
                scanObjective = 10
            default:
                break
            }
        }
    }
    
    private func importLayer(from dir: UInt32) {
        if let w: UInt32 = TIFFGetField(tiff, TIFFTAG_IMAGEWIDTH),
           let h: UInt32 = TIFFGetField(tiff, TIFFTAG_IMAGELENGTH) {
            layerDir.append(dir)
            layerImageSize.append((Int(w), Int(h)))
            layerTileSize.append((
                Int(ceil(Double(h) / Double(tileTrait.size.h))),
                Int(ceil(Double(w) / Double(tileTrait.size.w)))
            ))
        }
    }    
}