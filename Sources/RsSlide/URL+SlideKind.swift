import Foundation
import RsFoundation

public struct SlideProvider {
    public let makePreview: () -> SlidePreview
    public let makeView: () -> Slide?
    // let makeUpload: () -> Slide?

    init(_ makePreview: @escaping () -> SlidePreview, _ makeView: @escaping () -> Slide?) {
        self.makePreview = makePreview
        self.makeView = makeView
        // self.makeUpload = makeView
    }
}

public enum SlideTrait: Equatable {
    case isSlide(SlideProvider)
    case isMetadataFolder
    case isGenericFolder
    case isGenericFile
    case notSupported

    public static func == (lhs: SlideTrait, rhs: SlideTrait) -> Bool {
        switch (lhs, rhs) {
        case (.isSlide, .isSlide),
            (.isMetadataFolder, .isMetadataFolder),
            (.isGenericFolder, .isGenericFolder),
            (.isGenericFile, .isGenericFile),
            (.notSupported, notSupported):
            return true
        default:
            return false
        }
    }
}

extension URL {
    public var slideTrait: SlideTrait {
        guard self.isFileURL else {
            log.trace("Not support \(self)")
            return .notSupported
        }

        let name = self.lastPathComponent.lowercased()
        if self.hasDirectoryPath {
            if name.hasSuffix(".dsmeta") {
                return .isMetadataFolder
            }
            #if MORE_PROVIDERS_AVAILABLE
                if let url = reachableChild(named: "1.mds") {
                    log.trace("Found 1.mds in \(url.path)")
                    return .isSlide(SlideProvider({ MDSPreview(path: url) }, { MDS(path: url) }))
                }
                if let url = reachableChild(named: "1.mdsx") {
                    log.trace("Found 1.mdsx in \(url.path)")
                    return .isSlide(SlideProvider({ VMSDKPreview(path: url) }, { VMSDK(path: url) }))
                }
            #endif

            return .isGenericFolder
        }

        if name.hasSuffix(".ome.tif") || name.hasSuffix(".ome.tiff") {
            return .isSlide(SlideProvider({ OMETIFFPreview(path: self) }, { OMETIFF(path: self) }))
        }
        if name.hasSuffix(".svs") || name.hasSuffix(".tif") || name.hasSuffix(".tiff") {
            return .isSlide(SlideProvider({ SVSPreview(path: self) }, { SVS(path: self) }))
        }
        if name.hasSuffix(".csp") {
            return .isSlide(SlideProvider({ CSPPreview(path: self) }, { CSP(path: self) }))
        }
        if name.hasSuffix(".qptiff") {
            return .isSlide(SlideProvider({ QPTIFFPreview(path: self) }, { QPTIFF(path: self) }))
        }
        #if MORE_PROVIDERS_AVAILABLE
            if name.hasSuffix(".mds") {
                return .isSlide(SlideProvider({ MDSPreview(path: self) }, { MDS(path: self) }))
            }
            if name.hasSuffix(".mdsx") || name.hasSuffix(".mdss") {
                return .isSlide(SlideProvider({ VMSDKPreview(path: self) }, { VMSDK(path: self) }))
            }
        #endif

        log.trace("Not slide \(self.path)")
        return .isGenericFile
    }
}
