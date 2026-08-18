import Foundation

public enum SlideExportError: Error {
    case unsupportedExportFormat(url: URL)
    case imageTooLarge(width: Int?, height: Int?)
    case insufficientMemoryForPixelData
    case failedToCompressJPEG
    case failedToCreateFile(url: URL)
    case failedToWriteFile(url: URL)
}

extension Slide {
    public func convert(to url: URL) throws {
        let fn = url.lastPathComponent.lowercased()
        if fn.hasSuffix(".svs") {
            try convert(toSVS: url)
        } else if fn.hasSuffix(".ome.tif") || fn.hasSuffix(".ome.tiff") {
            // try convert(toOMETIFF: url)
        } else {
            throw SlideExportError.unsupportedExportFormat(url: url)
        }
    }

    public func crop(rect: CGRect? = nil, to url: URL) throws {
        let maxRect = CGRect(x: 0, y: 0, width: layerImageSize[0].w, height: layerImageSize[0].h)
        let rect = (rect ?? maxRect).intersection(maxRect)
        let fn = url.lastPathComponent.lowercased()

        if fn.hasSuffix(".jpg") || fn.hasSuffix(".jpeg") {
            try crop(rect: rect, toJPEG: url)
        } else if fn.hasSuffix(".tif") || fn.hasSuffix(".tiff") {
            try crop(rect: rect, toTIFF: url)
        } else {
            throw SlideExportError.unsupportedExportFormat(url: url)
        }
    }
}
