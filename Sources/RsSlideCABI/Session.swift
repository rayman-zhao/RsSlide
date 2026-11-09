// C ABI exports exposed from RsSlideCABI.dll for C++ consumers (RsShell's
// thumbnail worker loads the DLL via LoadLibrary). Contracts are mirrored in
// RsShell/Explorer/SlideShim.h — changing either side must sync the other.
// JPEG buffers are allocated with CoTaskMemAlloc here and freed by the caller
// with CoTaskMemFree.
#if canImport(WinSDK)
    import Foundation
    import RsSlide
    import WinSDK

    /// One opened slide kept alive across raster fetches so pane resizes skip the
    /// full reparse (`makeSlide` walks every TIFF directory); releasing the
    /// session drops the last reference and the provider deinit closes the file.
    final class SlideSession {
        let slide: Slide
        init?(_ factory: SlideFactory) {
            guard let slide = factory.makeSlide() else { return nil }
            self.slide = slide
        }
    }

    @_cdecl("RsSlideSessionOpen")
    public func rsSlideSessionOpen(
        path: UnsafePointer<CWideChar>?, outSession: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    ) -> HRESULT {
        guard let path, let outSession else { return eInvalidArg }
        outSession.pointee = nil
        guard let factory = slideFactory(path), let session = SlideSession(factory) else {
            return eFail
        }
        outSession.pointee = Unmanaged.passRetained(session).toOpaque()
        return HRESULT(0)  // S_OK
    }

    @_cdecl("RsSlideSessionClose")
    public func rsSlideSessionClose(session: UnsafeMutableRawPointer?) {
        guard let session else { return }
        _ = Unmanaged<SlideSession>.fromOpaque(session).takeRetainedValue()
    }

    /// Composited pyramid thumbnail of the opened session as a literal Windows
    /// bitmap raster: 24bpp BGR, bottom-up, stride DWORD-aligned
    /// ((width*3 + 3) & ~3), buffer = stride * height. A color slide converts
    /// directly; gray planes are fluorescence channels (single channel
    /// included — e.g. a DAPI-only scan) that additively compose into the
    /// buffer through their channel pseudo color, saturating at 255 — channels
    /// without a metadata color contribute nothing and are skipped unfetched.
    @_cdecl("RsSlideSessionThumbnailBitmap")
    public func rsSlideSessionThumbnailBitmap(
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
        let slide = Unmanaged<SlideSession>.fromOpaque(session)
            .takeUnretainedValue().slide

        // 通道 0 先取：定结果缓冲尺寸/行距，也是两条合成路的数据源与一致性基准
        guard let base = slide.fetchThumbnailPixelData(maxSize: Int(maxSize)) else {
            return eFail
        }
        let stride = (base.width * 3 + 3) & ~3
        guard let buffer = CoTaskMemAlloc(SIZE_T(stride * base.height)) else { return eOutOfMemory }
        let dst = buffer.assumingMemoryBound(to: UInt8.self)

        if slide.tileTrait.pixelFormat == .rgb {
            base.pixels.withUnsafeBufferPointer { src in
                for y in 0..<base.height {
                    let dstRow = stride * (base.height - 1 - y)
                    let srcRow = y * base.pitch
                    for x in 0..<base.width {
                        let s = srcRow + x * 3
                        let d = dstRow + x * 3
                        dst[d] = src[s + 2]
                        dst[d + 1] = src[s + 1]
                        dst[d + 2] = src[s]
                    }
                }
            }
        } else {
            memset(dst, 0, stride * base.height)

            // 灰度即荧光通道（含单通道，如纯 DAPI 扫描），一律按 pseudoColorRGB 着色；
            // 无色通道乘零贡献，跳过不取
            let channels = slide.channelTrait.count
            let colors: [(r: Int, g: Int, b: Int)] = slide.channelTrait.map { trait in
                let rgb = trait.pseudoColorRGB
                return ((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF)
            }

            for channel in 0..<channels {
                let color = colors[channel]
                guard color.r != 0 || color.g != 0 || color.b != 0 else { continue }
                let plane =
                    channel == 0
                    ? base
                    : slide.fetchThumbnailPixelData(maxSize: Int(maxSize), channel: channel)
                guard let plane, plane.width == base.width, plane.height == base.height,
                    plane.pitch == base.pitch
                else {
                    CoTaskMemFree(buffer)
                    return eFail
                }
                plane.pixels.withUnsafeBufferPointer { src in
                    for y in 0..<plane.height {
                        let dstRow = stride * (plane.height - 1 - y)
                        let srcRow = y * plane.pitch
                        for x in 0..<plane.width {
                            let v = Int(src[srcRow + x])
                            let d = dstRow + x * 3
                            dst[d] = UInt8(min(255, Int(dst[d]) + v * color.b / 255))
                            dst[d + 1] = UInt8(min(255, Int(dst[d + 1]) + v * color.g / 255))
                            dst[d + 2] = UInt8(min(255, Int(dst[d + 2]) + v * color.r / 255))
                        }
                    }
                }
            }
        }

        outBitmap.pointee = dst
        outWidth.pointee = UInt32(base.width)
        outHeight.pointee = UInt32(base.height)
        return HRESULT(0)  // S_OK
    }
#endif
