import Foundation

public enum SlideExportError: Error {
    case unsupportedExportFormat(url: URL)
    case tooBigImageToExportJPEG(w: Int?, h: Int?)
    case noMemoryToFetchPixelData
    case noMemoryToExportJPEG
    case failedCreateSVSFile(url: URL)
    case failedWriteSVSDirectory
}

extension Slide {
    public func save(to url: URL) throws {
        let fn = url.lastPathComponent.lowercased()
        if fn.hasSuffix(".jpg") || fn.hasSuffix(".jpeg") {
            try saveAsJPEG(to: url)
        } else if fn.hasSuffix(".svs") {
            try saveAsSVS(to: url)
        } else if fn.hasSuffix(".ome.tif") || fn.hasSuffix(".ome.tiff") {
            // try saveAsOMETIFF(to: url)
        } else {
            throw SlideExportError.unsupportedExportFormat(url: url)
        }
    }
}
