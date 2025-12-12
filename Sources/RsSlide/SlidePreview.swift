import Foundation

public protocol SlidePreview {
    @available(*, deprecated, message: "Use return Array version")
    func fetchMacroJPEGImage() -> Data

    func fetchMacroJPEGImage() -> [UInt8]
}
