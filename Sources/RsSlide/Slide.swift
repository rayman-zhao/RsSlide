import Foundation
import LibJPEGTurbo
import MBL
import RsHelper

public struct TileCoordinate {
    let layer: Int
    let row: Int
    let col: Int
    let tier: Int
    let channel: Int
    
    public init(layer: Int, row: Int, col: Int) {
        self.layer = layer
        self.row = row
        self.col = col
        self.tier = 0
        self.channel = 0
    }
    public init(layer: Int, row: Int, col: Int, tier: Int) {
        self.layer = layer
        self.row = row
        self.col = col
        self.tier = tier
        self.channel = 0
    }
    public init(layer: Int, row: Int, col: Int, channel: Int) {
        self.layer = layer
        self.row = row
        self.col = col
        self.tier = 0
        self.channel = channel
    }
}

public struct TileTrait: CustomStringConvertible {
    public enum CompressionHint {
        case jpeg
        case png
        case jxl
    }
    public enum PixelFormatHint: Int {
        case rgb = 3
        case gray = 1
    }
    
    public let size: (w: Int, h: Int)
    public let compression: CompressionHint
    public let pixelFormat: PixelFormatHint
    public let sampleBits: Int
    public let rgbBackground: Int
    
    public var description: String {
        switch (compression, pixelFormat, sampleBits) {
        case (.jpeg, .rgb, 8):
            return "JPEG_RGB_24bits"
        default:
            fatalError()
        }
    }
    
    public var maxBytes: Int {
        return size.h * pitchBytes
    }

    public var pixelBytes: Int {
        return pixelFormat.rawValue * sampleBits / 8
    }

    public var pitchBytes: Int {
        return size.w * pixelBytes
    }

    public var tjPF: TJPF {
        switch pixelFormat {
        case .rgb:
            return TJPF_RGB
        case .gray:
            return TJPF_GRAY
        }
    }
    
    init(width: Int, height: Int,
         compression: CompressionHint = .jpeg,
         pixelFormat: PixelFormatHint = .rgb,
         sampleBits: Int = 8,
         rgbBackground: Int = 0xFFFFFF) {
        self.size = (width, height)
        self.compression = compression
        self.pixelFormat = pixelFormat
        self.sampleBits = sampleBits
        self.rgbBackground = rgbBackground
    }
}

public protocol Slide {
    var id: UUID { get }
    var mainPath: String { get }
    var createTime: Date { get }
    var modifyTime: Date { get }
    var name: String { get }
    var format: String { get }
    var dataSize: Int { get }
    var scanObjective: Int { get }
    var scanScale: Double { get }
    var tileTrait: TileTrait { get }
    var layerZoom: Int { get }
    var extendXMLString: String { get }

    var layerImageSize: [(w: Int, h: Int)] { get }
    var layerTileSize: [(r: Int, c: Int)] { get }
    var tierCount: Int { get }
    var tierSpacing: Double { get }

    var baseLayerPixelData: (pixels: [UInt8], layer: Int, width: Int, pitch: Int, height: Int)? { get }

    func fetchLabelJPEGImage() -> [UInt8]?
    func fetchMacroJPEGImage() -> [UInt8]?
    func fetchTileRawImage(at coord: TileCoordinate) -> [UInt8]?
}

public extension Slide {
    func fetchTileImage(at coord: TileCoordinate) -> [UInt8]? {
        switch validate(coord: coord) {
            case .valid(trimming: false):
                return fetchTileRawImage(at: coord)
            case .valid(trimming: true):
                return fetchTrimmedTileImage(at: coord)
            case .virtual:
                return fetchVirtualTileImage(at: coord)
            case .invalid:
                return nil
        }
    }

    func fetchThumbnailJPEGImage(with maxSize: Int = 512) -> [UInt8]? {
        guard tileTrait.pixelFormat == .rgb
            && tileTrait.sampleBits == 8
            && tileTrait.compression == .jpeg else {
            log.error("Failed to fetch thumbnail JPEG image. Only support RGB24 JPEG format slide file.")
            return nil
        }

        // Find the most suitable layer for thumbnail generation.
        var layer = layerImageSize.count - 1
        while (layer > 0 && layerImageSize[layer].w < maxSize && layerImageSize[layer].h < maxSize) {
            layer -= 1
        }
        
        guard layer >= 0 else { return nil }
        guard let pxdata = fetchPixelData(at: layer) else { return nil }

        var thumbnailWidth = maxSize
        var thumbnailHeight = maxSize
        if pxdata.width > pxdata.height {
            thumbnailHeight = thumbnailWidth * pxdata.height / pxdata.width
        } else if pxdata.width < pxdata.height {
            thumbnailWidth = thumbnailHeight * pxdata.width / pxdata.height
        }

        if (thumbnailWidth, thumbnailHeight) == (pxdata.width, pxdata.height) {
            return tjCompress(pxdata.pixels, tileTrait.tjPF, pxdata.width, pxdata.height, pxdata.pitch)
        } else {
            let trimmed = trimPixelData(from: pxdata)
            let thumbnail = scaleImage(trimmed.pixels, trimmed.width, trimmed.height, thumbnailWidth, thumbnailHeight)
            return tjCompress(thumbnail, tileTrait.tjPF, thumbnailWidth, thumbnailHeight)
        }
    }
}

public enum SlideExportError: Error {
    case unsupportedExportFormat(url: URL)
    case tooBigImageToExportJPEG(w: Int?, h: Int?)
    case noMemoryToFetchPixelData
    case noMemoryToExportJPEG
    case failedCreateSVSFile(url: URL)
    case failedWriteSVSDirectory
}

public extension Slide {
    func save(as url: URL) throws {
        let fn = url.lastPathComponent.lowercased()
        if fn.hasSuffix(".jpg") || fn.hasSuffix(".jpeg") {
            try saveAsJPEG(to: url)
        } else if fn.hasSuffix(".svs") {
            try saveAsSVS(to: url)
        } else if fn.hasSuffix(".ome.tif") || fn.hasSuffix(".ome.tiff") {
            // try saveTIFF(as: url)
        } else {
            throw SlideExportError.unsupportedExportFormat(url: url)
        }
    }
}
