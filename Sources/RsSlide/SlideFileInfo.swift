import Foundation
import RsFoundation

/// File-level metadata snapshot, read from disk once and shared by previews and slides.
///
/// - Important: Do not use `URL.resourceValues` here — it traps on files larger than
///   2 GiB on Windows (Int32 overflow inside corelibs-foundation), while
///   `FileManager` handles them fine.
struct SlideFileInfo {
    let mainURL: URL
    let mainPath: String
    let name: String
    let format: String

    let createTime: Date
    let modifyTime: Date
    let dataSize: Int

    init(url: URL) {
        mainURL = url
        mainPath = url.filePath

        let fileName = url.lastPathComponent
        let fileNameLower = fileName.lowercased()
        if fileNameLower.hasSuffix(".ome.tif") {
            name = String(fileName.dropLast(8))
            format = "OME.TIF"
        } else if fileNameLower.hasSuffix(".ome.tiff") {
            name = String(fileName.dropLast(9))
            format = "OME.TIFF"
        } else {
            format = url.pathExtension.uppercased()
            if fileNameLower == "1.mds" || fileNameLower == "1.mdsx" {
                name = url.deletingLastPathComponent().lastPathComponent
            } else {
                name = url.deletingPathExtension().lastPathComponent
            }
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        createTime = (attrs?[.creationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
        modifyTime = (attrs?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
        dataSize = (attrs?[.size] as? NSNumber)?.intValue ?? -1
    }
}

/// Internal conformance for file-backed previews: adopt this to get the `SlidePreview`
/// property requirements implemented from a `SlideFileInfo` snapshot, keeping `fileInfo`
/// out of the public interface.
protocol InternalSlidePreview: SlidePreview {
    var fileInfo: SlideFileInfo { get }
}

extension InternalSlidePreview {
    var createTime: Date { fileInfo.createTime }
    var name: String { fileInfo.name }
    var format: String { fileInfo.format }
    var dataSize: Int { fileInfo.dataSize }
}

protocol InternalSlide: Slide {
    var fileInfo: SlideFileInfo { get }
}

extension InternalSlide {
    var mainPath: String { fileInfo.mainPath }
    var name: String { fileInfo.name }
    var format: String { fileInfo.format }
    var createTime: Date { fileInfo.createTime }
    var modifyTime: Date { fileInfo.modifyTime }
    var dataSize: Int { fileInfo.dataSize }
}
