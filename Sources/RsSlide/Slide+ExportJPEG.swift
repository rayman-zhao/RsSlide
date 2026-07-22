import Foundation
import LibJPEGTurbo

extension Slide {
    func saveAsJPEG(to url: URL) throws {
        var layer: Int? = nil
        for img in layerImageSize.enumerated() {
            if img.element.w < UInt16.max && img.element.h < UInt16.max {
                layer = img.offset
                break
            }
        }
        guard let layer else { throw SlideExportError.imageTooLargeForJPEG(width: layerImageSize.last?.w, height: layerImageSize.last?.h) }
        guard let pxdata = fetchPixelData(at: layer) else { throw SlideExportError.insufficientMemoryForPixelData }
        let jpeg = tjCompress(pxdata.pixels, tileTrait.tjPF, pxdata.width, pxdata.height, pxdata.pitch)
        guard !jpeg.isEmpty else { throw SlideExportError.insufficientMemoryForJPEG }

        try Data(jpeg).write(to: url)
    }
}
