import Foundation
import RsFoundation

public struct SlideFactory {
    public let makePreview: () -> SlidePreview
    public let makeSlide: () -> Slide?

    public init(preview: @escaping () -> SlidePreview, slide: @escaping () -> Slide?) {
        self.makePreview = preview
        self.makeSlide = slide
    }
}

public enum SlideKind: Equatable {
    case slide(SlideFactory)
    case metadataFolder
    case genericFolder
    case genericFile
    case notSupported

    public static func == (lhs: SlideKind, rhs: SlideKind) -> Bool {
        switch (lhs, rhs) {
        case (.slide, .slide),
            (.metadataFolder, .metadataFolder),
            (.genericFolder, .genericFolder),
            (.genericFile, .genericFile),
            (.notSupported, notSupported):
            return true
        default:
            return false
        }
    }
}

extension URL {
    /// The slide kind of this URL, detected by extension and directory inspection.
    ///
    /// - Complexity: O(*k*) file-system stat calls, where *k* is the number of candidate children inspected.
    public var slideKind: SlideKind {
        guard self.isFileURL else {
            log.trace("Not support \(self)")
            return .notSupported
        }

        let name = self.lastPathComponent.lowercased()
        if self.hasDirectoryPath {
            if name.hasSuffix(".dsmeta") {
                return .metadataFolder
            }
            #if MORE_PROVIDERS_AVAILABLE
                if let url = reachableChild(named: "1.mds") {
                    log.trace("Found 1.mds in \(url.path)")
                    return .slide(SlideFactory(preview: { MDSPreview(path: url) }, slide: { MDS(path: url) }))
                }
                if let url = reachableChild(named: "1.mdsx") {
                    log.trace("Found 1.mdsx in \(url.path)")
                    return .slide(SlideFactory(preview: { VMSDKPreview(path: url) }, slide: { VMSDK(path: url) }))
                }
            #endif

            return .genericFolder
        }

        if name.hasSuffix(".ome.tif") || name.hasSuffix(".ome.tiff") {
            return .slide(SlideFactory(preview: { OMETIFFPreview(path: self) }, slide: { OMETIFF(path: self) }))
        }
        if name.hasSuffix(".svs") || name.hasSuffix(".tif") || name.hasSuffix(".tiff") {
            return .slide(SlideFactory(preview: { SVSPreview(path: self) }, slide: { SVS(path: self) }))
        }
        if name.hasSuffix(".csp") {
            return .slide(SlideFactory(preview: { CSPPreview(path: self) }, slide: { CSP(path: self) }))
        }
        if name.hasSuffix(".qptiff") {
            return .slide(SlideFactory(preview: { QPTIFFPreview(path: self) }, slide: { QPTIFF(path: self) }))
        }
        #if MORE_PROVIDERS_AVAILABLE
            if name.hasSuffix(".mds") {
                return .slide(SlideFactory(preview: { MDSPreview(path: self) }, slide: { MDS(path: self) }))
            }
            if name.hasSuffix(".mdsx") || name.hasSuffix(".mdss") {
                return .slide(SlideFactory(preview: { VMSDKPreview(path: self) }, slide: { VMSDK(path: self) }))
            }
        #endif

        log.trace("Not slide \(self.path)")
        return .genericFile
    }
}
