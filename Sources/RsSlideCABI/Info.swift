// C ABI exports exposed from RsSlideCABI.dll for C++ consumers (RsShell's
// thumbnail worker loads the DLL via LoadLibrary). Contracts are mirrored in
// RsShell/Explorer/SlideShim.h — changing either side must sync the other.
// JPEG buffers are allocated with CoTaskMemAlloc here and freed by the caller
// with CoTaskMemFree.
#if canImport(WinSDK)
    import Foundation
    import RsSlide
    import WinSDK

    /// Byte size of the fixed header that opens the `RsSlideInfo`
    /// buffer; mirrored with offsetof static_asserts in SlideShim.h.
    private let infoHeaderBytes = 64

    /// Slide metadata for the Shell property handler: a 64-byte fixed header
    /// (width/height/bitDepth/levelCount, mpp, objective, keywordCount,
    /// tierCount, tileWidth/tileHeight, tileCompression, tilePixelFormat,
    /// reserved) in one CoTaskMem buffer. `mpp`/`objective` are 0 when
    /// unknown. The consumer rebuilds TileTrait.description from
    /// tileCompression/tilePixelFormat/bitDepth; `bitDepth`/`levelCount`/
    /// tier count ride along unmapped, reserved for future property keys.
    /// `keywordCount` stays 0 — the channelTrait default stain name ("H&E")
    /// is not reliably true, so no keyword source is emitted; the field keeps
    /// the ABI slot for a real source (e.g. Aperio Stain lines) and the raw
    /// ImageDescription (patient data) must never leak in.
    @_cdecl("RsSlideInfo")
    public func rsSlideInfo(
        path: UnsafePointer<CWideChar>?,
        outInfo: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?
    ) -> HRESULT {
        guard let path, let outInfo else { return eInvalidArg }
        outInfo.pointee = nil
        guard let factory = slideFactory(path), let slide = factory.makeSlide(),
            let base = slide.layerImageSize.first
        else { return eFail }

        guard let buffer = CoTaskMemAlloc(SIZE_T(infoHeaderBytes)) else { return eOutOfMemory }
        buffer.storeBytes(of: UInt32(base.w), toByteOffset: 0, as: UInt32.self)
        buffer.storeBytes(of: UInt32(base.h), toByteOffset: 4, as: UInt32.self)
        buffer.storeBytes(of: UInt32(slide.tileTrait.sampleBits), toByteOffset: 8, as: UInt32.self)
        buffer.storeBytes(of: UInt32(slide.layerImageSize.count), toByteOffset: 12, as: UInt32.self)
        buffer.storeBytes(of: slide.scanScale, toByteOffset: 16, as: Double.self)
        buffer.storeBytes(of: slide.scanObjective, toByteOffset: 24, as: Double.self)
        // CoTaskMemAlloc 不清零：保留槽位（keywordCount/reserved）显式写 0
        buffer.storeBytes(of: UInt32(0), toByteOffset: 32, as: UInt32.self)
        // CompressionHint 声明序：0=jpeg 1=png 2=jxl；PixelFormatHint.rawValue 恰为通道数
        let compression =
            slide.tileTrait.compression == .jpeg ? 0 : slide.tileTrait.compression == .png ? 1 : 2
        buffer.storeBytes(of: UInt32(slide.tierTrait.count), toByteOffset: 36, as: UInt32.self)
        buffer.storeBytes(of: UInt32(slide.tileTrait.size.w), toByteOffset: 40, as: UInt32.self)
        buffer.storeBytes(of: UInt32(slide.tileTrait.size.h), toByteOffset: 44, as: UInt32.self)
        buffer.storeBytes(of: UInt32(compression), toByteOffset: 48, as: UInt32.self)
        buffer.storeBytes(
            of: UInt32(slide.tileTrait.pixelFormat.rawValue), toByteOffset: 52, as: UInt32.self)
        buffer.storeBytes(of: UInt32(0), toByteOffset: 56, as: UInt32.self)

        outInfo.pointee = buffer.assumingMemoryBound(to: UInt8.self)
        return HRESULT(0)  // S_OK
    }
#endif
