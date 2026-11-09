import Foundation
import RsFoundation
import WinSDK

final class DLLLoader {
    private let dll: HMODULE?

    init(name: String, folder: String) {
        // Two vendor-DLL layouts, both anchored at the directory of the linking
        // module (the host exe/DLL RsSlide is statically linked into): a
        // <folder>/ beside the module (RjSlide, RsSlide dev layout), or the
        // Ruslan app-bundle layout when the module sits at a package root
        // (Ruslan, RsShell's thumbnail worker). Bundle.main is not consulted:
        // with static linking the module *is* the host exe (same directory),
        // and when the host process runs from elsewhere (JVM, COM surrogate)
        // Bundle.main points at an unrelated path — only the module anchor works.
        var path: String = name
        if let root = SystemProcess.moduleDirectory {
            path =
                root.reachableChild(named: "\(folder)/\(name).dll")?.filePath
                ?? root.reachableChild(
                    named: "Ruslan_Ruslan.bundle/CloudExec/lib/\(folder)/\(name).dll")?.filePath
                ?? path
        }

        path = path.replacingOccurrences(of: "/", with: "\\")  // LoadLibraryEx requires backslash, LoadLibrary does not.
        dll = LoadLibraryExW(
            path.wideString, nil,
            DWORD(LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS))  // Load other dependencies from the same DLL folder.
        if dll != nil {
            log.info("Successfully loaded \(path)")
        } else {
            log.error("Failed to load \(path)")
        }
    }

    deinit {
        if let dll {
            FreeLibrary(dll)
        }
    }

    func getProc<T>(_ name: String) -> T? {
        guard let dll, let pfn = GetProcAddress(dll, name) else { return nil }
        return unsafeBitCast(pfn, to: T.self)
    }
}
