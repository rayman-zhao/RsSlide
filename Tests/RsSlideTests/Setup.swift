import Foundation
import Testing

let ENV = ProcessInfo.processInfo.environment

let BASE = URL(
    filePath: ENV["RUSLAN_TEST_BASE"] ?? "/Users/zhaoyu/Desktop/Slides/",
    directoryHint: .isDirectory
)