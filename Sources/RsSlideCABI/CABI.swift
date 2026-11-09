// C ABI exports exposed from RsSlideCABI.dll for C++ consumers (RsShell's
// thumbnail worker loads the DLL via LoadLibrary). Contracts are mirrored in
// RsShell/Explorer/SlideShim.h — changing either side must sync the other.
// JPEG buffers are allocated with CoTaskMemAlloc here and freed by the caller
// with CoTaskMemFree.
#if canImport(WinSDK)
    import Foundation
    import RsSlide
    import WinSDK

    // WinSDK does not import the winerror.h HRESULT macros; values below are
    // E_INVALIDARG / E_FAIL / E_OUTOFMEMORY.
    let eInvalidArg = HRESULT(bitPattern: 0x8007_0057)
    let eFail = HRESULT(bitPattern: 0x8000_4005)
    let eOutOfMemory = HRESULT(bitPattern: 0x8007_000E)

    func slideFactory(_ path: UnsafePointer<CWideChar>) -> SlideFactory? {
        guard let path = String(cWideString: path),
            case .slide(let factory) = URL(filePath: path).slideKind
        else { return nil }

        return factory
    }
#endif
