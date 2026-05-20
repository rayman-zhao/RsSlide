import Foundation
import WinSDK
import RsHelper

final class DllLoader {
    private let dll: HMODULE?

    init(_ name: String) {
        var path: String = name
        if let url = Bundle.main.url(forResource: name, withExtension: ".dll", subdirectory: "Ruslan_Ruslan.resources/CloudExec/lib") {
            path = url.filePath
        } else if let url = Bundle.main.url(forResource: name, withExtension: ".dll") {
            path = url.filePath
        } else if let module = GetModuleHandleW("RjSlide".wideString) {
            var buf = [CWideChar](repeating: 0, count: Int(MAX_PATH))
            let bufSize = GetModuleFileNameW(module, &buf, UInt32(buf.count))
            if bufSize > 0 {
                let rjSlideUrl = URL(filePath: String(decoding: Array(buf[..<Int(bufSize)]), as: UTF16.self))
                if let url = rjSlideUrl.reachableSibling(named: "\(name).dll") {
                    path = url.filePath
                }
            }
        }
        
        dll = LoadLibraryW(path.wideString)
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
