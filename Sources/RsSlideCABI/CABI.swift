// C ABI exports exposed from RsSlideCABI.dll for C++ consumers (RsShell's
// thumbnail worker loads the DLL via LoadLibrary). Contracts are mirrored in
// RsShell/Explorer/SlideShim.h — changing either side must sync the other.
// JPEG buffers are allocated with CoTaskMemAlloc here and freed by the caller
// with CoTaskMemFree.
#if canImport(WinSDK)
    import Foundation
    import LibJPEGTurbo
    import RsSlide
    import WinSDK

    // WinSDK does not import the winerror.h HRESULT macros; values below are
    // E_INVALIDARG / E_FAIL / E_OUTOFMEMORY.
    private let eInvalidArg = HRESULT(bitPattern: 0x8007_0057)
    private let eFail = HRESULT(bitPattern: 0x8000_4005)
    private let eOutOfMemory = HRESULT(bitPattern: 0x8007_000E)

    private func slideFactory(_ path: UnsafePointer<CWideChar>) -> SlideFactory? {
        guard let path = String(cWideString: path),
            case .slide(let factory) = URL(filePath: path).slideKind
        else { return nil }

        return factory
    }

    private func returnJpeg(
        _ jpeg: [UInt8],
        _ outJpeg: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
        _ outSize: UnsafeMutablePointer<Int>
    ) -> HRESULT {
        guard let buffer = jpeg.withUnsafeBufferPointer({ CoTaskMemAlloc(SIZE_T($0.count)) }) else {
            return eOutOfMemory
        }
        jpeg.withUnsafeBytes { raw in
            UnsafeMutableRawBufferPointer(start: buffer, count: jpeg.count).copyBytes(from: raw)
        }
        outJpeg.pointee = buffer.assumingMemoryBound(to: UInt8.self)
        outSize.pointee = jpeg.count
        return HRESULT(0)  // S_OK
    }

    /// Slide preview (macro image) as a literal Windows bitmap raster: 32bpp
    /// BGRA (alpha opaque), bottom-up rows, stride = width * 4 (always
    /// DWORD-aligned), buffer size = stride * height, native macro resolution;
    /// `maxSize` is reserved. Covers both macro routes — direct pixel read, or
    /// the stored JPEG decompressed in-place (tjDecompress emits BGRA with
    /// alpha forced to the maximum sample). Fails only when the format has no
    /// macro at all; callers fall back to `RsSlideThumbnail`.
    @_cdecl("RsSlidePreviewBitmap")
    public func rsSlidePreviewBitmap(
        path: UnsafePointer<CWideChar>?,
        maxSize: UInt32,
        outBitmap: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
        outWidth: UnsafeMutablePointer<UInt32>?,
        outHeight: UnsafeMutablePointer<UInt32>?
    ) -> HRESULT {
        guard let path, let outBitmap, let outWidth, let outHeight, maxSize > 0 else {
            return eInvalidArg
        }
        outBitmap.pointee = nil
        outWidth.pointee = 0
        outHeight.pointee = 0
        guard let factory = slideFactory(path) else { return eFail }
        let preview = factory.makePreview()

        func publish(_ buffer: UnsafeMutableRawPointer?, _ width: Int, _ height: Int) -> HRESULT {
            outBitmap.pointee = buffer?.assumingMemoryBound(to: UInt8.self)
            outWidth.pointee = UInt32(width)
            outHeight.pointee = UInt32(height)
            return HRESULT(0)  // S_OK
        }

        // 两条宏图路都直接写 CoTaskMem 缓冲，无中间数组与拷贝
        if let image = preview.fetchMacroRGBAImage() {
            let stride = image.width * 4
            guard let buffer = CoTaskMemAlloc(SIZE_T(stride * image.height)) else {
                return eOutOfMemory
            }
            // RGBAImage 栅格是小端 uint32、内存序 R,G,B,A、顶朝下；转 BGRA 并翻行
            image.pixels.withUnsafeBufferPointer { src in
                let dst = buffer.assumingMemoryBound(to: UInt8.self)
                for y in 0..<image.height {
                    let dstRow = stride * (image.height - 1 - y)
                    for x in 0..<image.width {
                        let px = src[y * image.width + x]
                        dst[dstRow + x * 4] = UInt8(truncatingIfNeeded: px >> 16)
                        dst[dstRow + x * 4 + 1] = UInt8(truncatingIfNeeded: px >> 8)
                        dst[dstRow + x * 4 + 2] = UInt8(truncatingIfNeeded: px)
                        dst[dstRow + x * 4 + 3] = UInt8(truncatingIfNeeded: px >> 24)
                    }
                }
            }
            return publish(buffer, image.width, image.height)
        }

        if let jpeg = preview.fetchMacroJPEGImage() {
            let header = tjDecompressHeader(jpeg)
            guard header.width > 0, header.height > 0 else { return eFail }
            guard let buffer = CoTaskMemAlloc(SIZE_T(header.width * 4 * header.height))
            else { return eOutOfMemory }
            // turbojpeg 原生 BGRA + 自底向上，alpha 保证 255，零后处理
            guard tjDecompress(jpeg, TJPF_BGRA, into: buffer, header.width * 4, true) != nil
            else {
                CoTaskMemFree(buffer)
                return eFail
            }
            return publish(buffer, header.width, header.height)
        }

        return eFail
    }

    /// Pyramid-layer thumbnail — full slide parse, much heavier than the preview
    /// path; kept for callers that need an image even when the macro is missing.
    @_cdecl("RsSlideThumbnail")
    public func rsSlideThumbnail(
        path: UnsafePointer<CWideChar>?,
        maxSize: UInt32,
        outJpeg: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
        outSize: UnsafeMutablePointer<Int>?
    ) -> HRESULT {
        guard let path, let outJpeg, let outSize, maxSize > 0 else { return eInvalidArg }
        outJpeg.pointee = nil
        outSize.pointee = 0
        guard let factory = slideFactory(path),
            let slide = factory.makeSlide(),
            let jpeg = slide.fetchThumbnailJPEGImage(maxSize: Int(maxSize))
        else { return eFail }
        return returnJpeg(jpeg, outJpeg, outSize)
    }

    /// One opened slide kept alive across raster fetches so pane resizes skip the
    /// full reparse (`makeSlide` walks every TIFF directory); releasing the
    /// session drops the last reference and the provider deinit closes the file.
    final class PreviewRasterSession {
        let slide: Slide
        init?(_ factory: SlideFactory) {
            guard let slide = factory.makeSlide() else { return nil }
            self.slide = slide
        }
    }

    // Pseudo-color fallback for channels whose metadata carries no color
    // (pseudoColorRGB == 0); DAPI blue first, then the usual fluorophore hues.
    private let fallbackPseudoColors: [Int] = [
        0x3366FF, 0x33CC33, 0xFF3333, 0xCC33CC, 0x33CCCC, 0xCCCC33, 0xFF8833, 0x8844CC,
    ]

    @_cdecl("RsSlidePreviewRasterOpen")
    public func rsSlidePreviewRasterOpen(
        path: UnsafePointer<CWideChar>?,
        outSession: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    ) -> HRESULT {
        guard let path, let outSession else { return eInvalidArg }
        outSession.pointee = nil
        guard let factory = slideFactory(path),
            let session = PreviewRasterSession(factory)
        else { return eFail }
        outSession.pointee = Unmanaged.passRetained(session).toOpaque()
        return HRESULT(0)  // S_OK
    }

    /// Composited pyramid thumbnail of the opened session as the same literal
    /// Windows bitmap raster contract as `RsSlidePreviewBitmap` (32bpp BGRA,
    /// alpha opaque, bottom-up, stride = width * 4): a color slide converts
    /// directly, a single-channel gray slide replicates, and a multi-channel
    /// fluorescent slide additively composites every gray plane through its
    /// channel pseudo color (saturating at 255).
    @_cdecl("RsSlidePreviewRaster")
    public func rsSlidePreviewRaster(
        session: UnsafeMutableRawPointer?,
        maxSize: UInt32,
        outBitmap: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
        outWidth: UnsafeMutablePointer<UInt32>?,
        outHeight: UnsafeMutablePointer<UInt32>?
    ) -> HRESULT {
        guard let session, let outBitmap, let outWidth, let outHeight, maxSize > 0 else {
            return eInvalidArg
        }
        outBitmap.pointee = nil
        outWidth.pointee = 0
        outHeight.pointee = 0
        let slide = Unmanaged<PreviewRasterSession>.fromOpaque(session)
            .takeUnretainedValue().slide

        guard let base = slide.fetchThumbnailRasterImage(maxSize: Int(maxSize)) else {
            return eFail
        }
        let stride = base.width * 4
        guard let buffer = CoTaskMemAlloc(SIZE_T(stride * base.height)) else { return eOutOfMemory }
        let dst = buffer.assumingMemoryBound(to: UInt8.self)

        if base.isColor {
            base.pixels.withUnsafeBufferPointer { src in
                for y in 0..<base.height {
                    let dstRow = stride * (base.height - 1 - y)
                    let srcRow = y * base.width * 3
                    for x in 0..<base.width {
                        let s = srcRow + x * 3
                        let d = dstRow + x * 4
                        dst[d] = src[s + 2]
                        dst[d + 1] = src[s + 1]
                        dst[d + 2] = src[s]
                        dst[d + 3] = 255
                    }
                }
            }
        } else if slide.channelTrait.count == 1 {
            base.pixels.withUnsafeBufferPointer { src in
                for y in 0..<base.height {
                    let dstRow = stride * (base.height - 1 - y)
                    let srcRow = y * base.width
                    for x in 0..<base.width {
                        let v = src[srcRow + x]
                        let d = dstRow + x * 4
                        dst[d] = v
                        dst[d + 1] = v
                        dst[d + 2] = v
                        dst[d + 3] = 255
                    }
                }
            }
        } else {
            var planes = [[UInt8]]()
            planes.reserveCapacity(slide.channelTrait.count)
            for channel in 0..<slide.channelTrait.count {
                guard
                    let plane = slide.fetchThumbnailRasterImage(
                        maxSize: Int(maxSize), channel: channel),
                    plane.width == base.width, plane.height == base.height
                else {
                    CoTaskMemFree(buffer)
                    return eFail
                }
                planes.append(plane.pixels)
            }
            let colors = (0..<slide.channelTrait.count).map { channel -> (Int, Int, Int) in
                let rgb =
                    slide.channelTrait[channel].pseudoColorRGB != 0
                    ? slide.channelTrait[channel].pseudoColorRGB
                    : fallbackPseudoColors[channel % fallbackPseudoColors.count]
                return ((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF)
            }
            planes.withUnsafeBufferPointer { buffers in
                for i in 0..<(base.width * base.height) {
                    var r = 0
                    var g = 0
                    var b = 0
                    for channel in 0..<buffers.count {
                        let v = Int(buffers[channel][i])
                        r += v * colors[channel].0
                        g += v * colors[channel].1
                        b += v * colors[channel].2
                    }
                    let d = stride * (base.height - 1 - i / base.width) + (i % base.width) * 4
                    dst[d] = UInt8(min(255, b / 255))
                    dst[d + 1] = UInt8(min(255, g / 255))
                    dst[d + 2] = UInt8(min(255, r / 255))
                    dst[d + 3] = 255
                }
            }
        }

        outBitmap.pointee = dst
        outWidth.pointee = UInt32(base.width)
        outHeight.pointee = UInt32(base.height)
        return HRESULT(0)  // S_OK
    }

    @_cdecl("RsSlidePreviewRasterClose")
    public func rsSlidePreviewRasterClose(session: UnsafeMutableRawPointer?) {
        guard let session else { return }
        Unmanaged<PreviewRasterSession>.fromOpaque(session).takeRetainedValue()
    }
#endif
