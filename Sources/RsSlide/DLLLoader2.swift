import Foundation
import WinSDK
import RsFoundation

final class DllLoader {
    private let dll: HMODULE?

    init(_ name: String, _ folder: String) {
        var path: String = name
        if let url = Bundle.main.url(forResource: name, withExtension: ".dll", subdirectory: "Ruslan_Ruslan.resources/CloudExec/lib/\(folder)") { // For Ruslan project
            path = url.filePath
        } else if let url = Bundle.main.url(forResource: name, withExtension: ".dll", subdirectory: "\(folder)") { // For RsSlide project
            path = url.filePath
        } else if let module = GetModuleHandleW("RjSlide".wideString) { // For RjSlide project
            var buf = [CWideChar](repeating: 0, count: Int(MAX_PATH))
            let bufSize = GetModuleFileNameW(module, &buf, UInt32(buf.count))
            if bufSize > 0 {
                let rjSlideUrl = URL(filePath: String(decoding: Array(buf[..<Int(bufSize)]), as: UTF16.self))
                if let folder = rjSlideUrl.reachableSibling(named: "\(folder)/"), let url = folder.reachableChild(named: "\(name).dll") {
                    path = url.filePath
                }
            }
        }

        path = path.replacingOccurrences(of: "/", with: "\\") // LoadLibraryEx requires backslash, LoadLibrary does not.
        dll = LoadLibraryExW(path.wideString, nil, DWORD(LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS)) // Load other dependencies from the same DLL folder.
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
