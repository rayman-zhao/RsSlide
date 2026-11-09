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
    @_cdecl("RsSlideThumbnailJpeg")
    public func rsSlideThumbnailJpeg(
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
#endif
