import Foundation
import Testing
import RsSlide

@Suite
struct TraitTests {
    @Test(arguments: [
        ("http://127.0.0.1/1.svs", "notSupported", false, false),
        ("https://localhost/1.svs", "notSupported", false, false),
        ("SVS/2312399.dsmeta/", "isMetadataFolder", false, false),
        ("x/", "isGenericFolder", false, false),
        ("KFB/2312399.kfb", "isGenericFile", false, false),
        ("MDSX/4/1.mdsx", "isGenericFile", false, false),
        ("SVS/2312399.svs", "isSlide", false, false),
        ("MDS/0002", "isSlide", true, true),
        ("MDS/0002/", "isSlide", true, true),
        ("MDS/0002/1.mds", "isSlide", true, false),
    ])
    func makeTrait(_ fn: String, _ st: String, _ more: Bool, _ dir: Bool) async throws {
        var url: URL? = nil
        if fn.starts(with: "http") {
            url = URL(string: fn)
        } else if dir && fn.last != "/" {
            url = URL(filePath: fn, directoryHint: .isDirectory, relativeTo: BASE)
        } else {
            url = URL(filePath: fn, relativeTo: BASE)
        }
        let trait = try #require(url).slideTrait

        switch st { // SlideTrait no need to be sendable only for parameter-testing.
        case "notSupported":
            #expect(trait == .notSupported)
        case "isSlide":
            var pvd: SlideProvider? = nil
            if case .isSlide(let p) = trait {
                pvd = p
            }
            #expect(more || pvd != nil)
        case "isGenericFile":
            #expect(trait == .isGenericFile)
        case "isMetadataFolder":
            #expect(trait == .isMetadataFolder)
        case "isGenericFolder":
            #expect(trait == .isGenericFolder)
        default:
            fatalError()
        }
    }
    
    @Test
    func listFolder() async throws {
        let enumerator = FileManager.default.enumerator(
            at: BASE,
            includingPropertiesForKeys: [.nameKey, .isDirectoryKey],
            options: .skipsHiddenFiles
        )!
        var slides: [String] = []
         
        while let file = enumerator.nextObject() as? URL {
            switch file.slideTrait{
            case .isSlide:
                if file.hasDirectoryPath {
                    slides.append("*\(file.lastPathComponent)")
                    enumerator.skipDescendants()
                }
                else {
                    slides.append("#\(file.lastPathComponent)")
                }
            case .isMetadataFolder:
                slides.append("-\(file.lastPathComponent)")
                enumerator.skipDescendants()
            case .isGenericFolder:
                slides.append(" \(file.path)")
            default:
                break
            }
        }
        
        for (i, s) in slides.enumerated() {
            print("#\(i + 1) \(s)")
        }
        #expect(slides.count > 0) // 应该在 UI 中显示出来的文件和文件夹。
    }
}