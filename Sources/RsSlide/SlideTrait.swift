import Foundation
import RsHelper

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
        case
            (.isSlide, .isSlide),
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

public extension URL {
    var slideTrait: SlideTrait {
        if !self.isFileURL {
            log.trace("Not support \(self)")
            return .notSupported
        }
        else if !self.hasDirectoryPath {
            switch self.pathExtension.lowercased() {
            case "svs", "tif":
                return .isSlide(SlideProvider({ SVSPreview(path: self) }, { SVS(path: self) }))
#if MORE_PROVIDERS_AVAILABLE
            case "mds":
                return .isSlide(SlideProvider({ MDSPreview(path: self) }, { MDS(path: self) }))
#endif
            default:
                log.trace("Not slide \(self.path)")
                return .isGenericFile
            }
        }
        else if self.lastPathComponent.contains(".dsmeta") {
            return .isMetadataFolder
        }
        else {
#if MORE_PROVIDERS_AVAILABLE
            if let url = reachableChild(named: "1.mds") {
                log.trace("Found 1.mds in \(url.path)")
                return .isSlide(SlideProvider({ MDSPreview(path: url) }, { MDS(path: url) }))
            }
#endif
            return .isGenericFolder
        }
    }
}
