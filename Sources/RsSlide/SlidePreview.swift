import Foundation

public protocol SlidePreview {
    var createTime: Date { get }
    var name: String { get }
    var dataSize: Int { get }

    func fetchMacroJPEGImage() -> [UInt8]?
}
