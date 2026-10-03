import Foundation
import LibJPEGTurbo

public protocol SlidePreview {
    var createTime: Date { get }
    var name: String { get }
    var format: String { get }
    var dataSize: Int { get }

    func fetchMacroJPEGImage() -> [UInt8]?
}

extension SlidePreview {
    /// Returns the macro image as JPEG data, losslessly rotated by the given angle.
    ///
    /// The rotation is applied directly to the JPEG's DCT coefficients without
    /// decoding to pixels, so the image is not recompressed and does not lose
    /// quality. The width and height swap when rotating by an odd multiple of
    /// 90 degrees.
    ///
    /// - Parameter rotationDegrees: The clockwise rotation in degrees, normalized
    ///   modulo 360, so `-90` rotates counter-clockwise by 90 degrees. Must be a
    ///   multiple of 90.
    /// - Returns: The rotated macro image, or `nil` if the macro image is
    ///   unavailable, `rotationDegrees` is not a multiple of 90, or the JPEG data
    ///   could not be transformed.
    public func fetchMacroJPEGImage(rotationDegrees: Int) -> [UInt8]? {
        guard let jpeg = fetchMacroJPEGImage() else { return nil }
        return tjRotate(jpeg, degrees: rotationDegrees)
    }
}
