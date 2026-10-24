import Foundation
import LibJPEGTurbo
import LibPNG

public struct TileCoordinate {
    let layer: Int
    let row: Int
    let col: Int
    let tier: Int
    let channel: Int

    public init(layer: Int, row: Int, col: Int, tier: Int = 0, channel: Int = 0) {
        self.layer = layer
        self.row = row
        self.col = col
        self.tier = tier
        self.channel = channel
    }
}

public struct TierTrait {
    public var count: Int = 1
    public var spacing: Double = 0.0
}

public struct ChannelTrait {
    public var name: String = "H&E"
    public var pseudoColorRGB: Int = 0
    public var wavelength: Int = 555
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
    public let backgroundColorRGB: Int

    var maxBytes: Int {
        return size.h * pitchBytes
    }

    var pixelBytes: Int {
        return pixelFormat.rawValue * sampleBits / 8
    }

    var pitchBytes: Int {
        return size.w * pixelBytes
    }

    var tjPF: TJPF {
        switch pixelFormat {
        case .rgb:
            return TJPF_RGB
        case .gray:
            return TJPF_GRAY
        }
    }

    var pngPF: PNGPixelFormat {
        switch pixelFormat {
        case .rgb:
            return .rgb
        case .gray:
            return .gray
        }
    }

    public var description: String {
        switch (compression, pixelFormat, sampleBits) {
        case (.jpeg, .rgb, 8):
            return "JPEG_RGB_24bits"
        case (.jpeg, .gray, 8):
            return "JPEG_GRAY_8bits"
        case (.png, .rgb, 8):
            return "PNG_RGB_24bits"
        case (.png, .gray, 8):
            return "PNG_GRAY_8bits"
        default:
            fatalError()
        }
    }

    init(
        width: Int, height: Int,
        compression: CompressionHint = .jpeg,
        pixelFormat: PixelFormatHint = .rgb,
        sampleBits: Int = 8,
        backgroundColorRGB: Int = 0xFFFFFF
    ) {
        self.size = (width, height)
        self.compression = compression
        self.pixelFormat = pixelFormat
        self.sampleBits = sampleBits
        self.backgroundColorRGB = backgroundColorRGB
    }
}

/// Pixel data of a slide layer, decompressed and packed row by row.
public struct LayerPixelData {
    let pixels: [UInt8]
    let layer: Int
    let width: Int
    let pitch: Int
    let height: Int
}

public protocol Slide {
    var mainPath: String { get }
    var name: String { get }
    var format: String { get }
    var createTime: Date { get }
    var modifyTime: Date { get }
    var dataSize: Int { get }

    var id: UUID { get }
    var tierTrait: TierTrait { get }
    var channelTrait: [ChannelTrait] { get }
    var tileTrait: TileTrait { get }

    var scanObjective: Double { get }
    var scanScale: Double { get }
    var extendedXML: String { get }

    var layerImageSize: [(w: Int, h: Int)] { get }
    var layerTileSize: [(r: Int, c: Int)] { get }
    var layerZoom: Int { get }

    /// Cached pixel data of the base (smallest) layer, generated once per provider.
    ///
    /// - Important: This is an implementation detail used internally by
    ///   `fetchVirtualTileImage`, `fetchThumbnailJPEGImage`, and `saveAsSVS`.
    ///   Do not access directly; treat it as if it were `internal`.
    var topLayerPixelData: [LayerPixelData?] { get }

    func fetchLabelJPEGImage() -> [UInt8]?
    func fetchMacroJPEGImage() -> [UInt8]?
    func fetchTileRawImage(for coord: TileCoordinate) -> [UInt8]?
}

extension Slide {
    public var layerZoom: Int {
        if layerTileSize.count > 1 {
            // The 2312399.svs has 4.00036166 zoom, so that use tile size instead.
            // layerZoom = Int(ceil(Double(layerImageSize[0].w) / Double(layerImageSize[1].w)))
            return Int(ceil(Double(layerTileSize[0].r) / Double(layerTileSize[1].r)))
        } else {
            return 2
        }
    }
}
