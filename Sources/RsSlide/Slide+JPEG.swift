import Foundation
import LibJPEGTurbo

extension Slide {
    func saveAsJPEG(to url: URL) throws {
        var layer: Int? = nil
        for img in layerImageSize.enumerated() {
            if img.element.w < Int32.max && img.element.h < Int32.max {
                layer = img.offset
                break
            }
        }
        guard let layer else { throw SlideExportError.tooBigImageToExportJPEG(w: layerImageSize.last?.w, h: layerImageSize.last?.h) }
        guard let pxdata = fetchPixelData(at: layer) else { throw SlideExportError.noMemoryToFetchPixelData }
        let jpeg = tjCompress(pxdata.pixels, tileTrait.tjPF, pxdata.width, pxdata.height, pxdata.pitch)
        guard !jpeg.isEmpty else { throw SlideExportError.noMemoryToExportJPEG }

        try Data(jpeg).write(to: url)
    }
}
