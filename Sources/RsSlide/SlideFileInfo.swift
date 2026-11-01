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

    /// Regular files of the slide folder (or, for a cellSens slide, of the
    /// companion `_basename_` stack folder, recursively), cached from the
    /// listing behind `dataSize` so consumers need not enumerate it again;
    /// empty for single-file slides.
    let children: [URL]

    init(url: URL) {
        mainURL = url
        mainPath = url.filePath

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        createTime = (attrs?[.creationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
        modifyTime = (attrs?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)

        let fileName = url.lastPathComponent
        let fileNameLower = fileName.lowercased()
        // Folder-type slides (`1.mds`/`1.mdsx`, a folder of DICOM instances) are
        // one slide per folder: named after the folder and sized by the total of
        // its files. Single-instance DICOM slides (a standalone VOLUME .dcm)
        // have not been seen yet; when one shows up, keep the stem name by
        // checking siblings here.
        if fileNameLower == "1.mds" || fileNameLower == "1.mdsx" || fileNameLower.hasSuffix(".dcm")
        {
            let folder = url.deletingLastPathComponent()
            name = folder.lastPathComponent
            format = url.pathExtension.uppercased()
            (dataSize, children) = Self.regularFiles(in: folder)
        } else if fileNameLower.hasSuffix(".vsi") {
            // A cellSens slide is a file-plus-folder composite: a small metadata
            // container whose pixels live in the sibling `_basename_` stack
            // folder, so it is sized and listed from both.
            name = url.deletingPathExtension().lastPathComponent
            format = "VSI"
            let stacks = Self.regularFiles(
                in: url.deletingLastPathComponent().appendingPathComponent("_\(name)_"),
                recursive: true)
            dataSize = Int((attrs?[.size] as? NSNumber)?.int64Value ?? 0) + stacks.totalSize
            children = stacks.children
        } else {
            if fileNameLower.hasSuffix(".ome.tif") {
                name = String(fileName.dropLast(8))
                format = "OME.TIF"
            } else if fileNameLower.hasSuffix(".ome.tiff") {
                name = String(fileName.dropLast(9))
                format = "OME.TIFF"
            } else {
                name = url.deletingPathExtension().lastPathComponent
                format = url.pathExtension.uppercased()
            }
            dataSize = Int((attrs?[.size] as? NSNumber)?.int64Value ?? -1)
            children = []
        }
    }

    /// The cached child matching the file name, case-insensitively; nil when
    /// absent.
    func child(named name: String) -> URL? {
        children.first { $0.lastPathComponent.lowercased() == name.lowercased() }
    }

    /// The regular files of a folder with their sizes; hidden files are skipped,
    /// subfolders only when `recursive` (the cellSens `stackN` layout nests).
    private static func regularFiles(
        in folder: URL, recursive: Bool = false
    ) -> (totalSize: Int, children: [URL]) {
        let listed =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []

        var totalSize = 0
        var children: [URL] = []
        for child in listed {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: child.path),
                let type = attrs[.type] as? FileAttributeType
            else { continue }

            if type == .typeRegular {
                children.append(child)
                totalSize += Int((attrs[.size] as? NSNumber)?.int64Value ?? 0)
            } else if recursive, type == .typeDirectory {
                let sub = regularFiles(in: child, recursive: true)
                children += sub.children
                totalSize += sub.totalSize
            }
        }
        return (totalSize, children)
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
    var modifyTime: Date { fileInfo.modifyTime }
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
