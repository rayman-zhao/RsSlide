import Foundation
import FoundationXML
import LibJPEGTurbo
import LibPNG
import Testing

@testable import RsSlide

let ENV = ProcessInfo.processInfo.environment

let BASE = URL(
    filePath: ENV["RUSLAN_TEST_BASE"] ?? "/Users/zhaoyu/Desktop/Slides/",
    directoryHint: .isDirectory
)

func evalMakeSlide(fromTrait trait: SlideKind) -> Slide? {
    guard case .slide(let builder) = trait else { fatalError() }

    let st = Date()
    let s = builder.makeSlide()
    let et = Date()
    print("Open consumed \(et.timeIntervalSince(st) * 1000) ms")
    return s
}

actor ExistingId {
    private var all: Set<UUID> = []

    func insertNew(_ item: UUID) -> Int {
        let cnt = all.count
        all.insert(item)
        return all.count - cnt
    }
}

let allIds = ExistingId()

func evalSlideMetadata(_ s: Slide) async {
    #expect(await allIds.insertNew(s.id) == 1)
    print("Slide GUID \(s.id)")

    #expect(s.dataSize > 0)
    print("File size \(s.dataSize)")

    #expect([10, 20, 40].contains(s.scanObjective))
    print("Scan objective \(s.scanObjective)")

    #expect(0.001...1 ~= s.scanScale)
    print("Scan scale \(s.scanScale)")

    #expect(s.tileTrait.size > (0, 0))
    print("Tile size \(s.tileTrait.size.w) x \(s.tileTrait.size.h)")
    #expect([24, 8].contains(s.tileTrait.sampleBits * s.tileTrait.pixelFormat.rawValue))
    #expect(s.tileTrait.maxBytes == s.tileTrait.size.w * s.tileTrait.size.h * 3)
    print("Tile format \(s.tileTrait)")

    #expect(s.layerImageSize.count == s.layerTileSize.count)
    #expect(s.layerImageSize.count > 0)
    for i in 0..<s.layerImageSize.count {
        print(
            "Layer \(i) \(s.layerImageSize[i].w)-\(s.layerImageSize[i].h) in \(s.layerTileSize[i].r)-\(s.layerTileSize[i].c)"
        )

        if i > 0 {
            let w = Int(ceil(Double(s.layerImageSize[i - 1].w) / Double(s.layerZoom)))
            let h = Int(ceil(Double(s.layerImageSize[i - 1].h) / Double(s.layerZoom)))
            #expect(0...1 ~= w - s.layerImageSize[i].w)
            #expect(0...1 ~= h - s.layerImageSize[i].h)
            #expect(s.layerTileSize[i - 1].r / s.layerZoom <= (s.layerTileSize[i].r + 1))
            #expect(s.layerTileSize[i - 1].c / s.layerZoom <= (s.layerTileSize[i].c + 1))
        }
    }

    #expect([2, 4].contains(s.layerZoom))
    print("Layer zoom \(s.layerZoom)")

    if !s.extendedXML.isEmpty {
        let xml = try? XMLDocument(xmlString: s.extendedXML)
        #expect(xml != nil)
        xml?.forEachElement { parent, name, attribute, value in
            print("\(parent)/\(name) - \(attribute) - \(value)")
        }
    }
}

func evalSlideLabelImage(_ s: Slide) throws {
    let st = Date()
    let img = Data(s.fetchLabelJPEGImage()!)
    let et = Date()
    print("Label image consumed \(et.timeIntervalSince(st) * 1000) ms")
    #expect(img.isJPEG)

    try img.write(
        to: URL(
            filePath: "\(s.name)_label.jpg",
            directoryHint: .notDirectory,
            relativeTo: BASE))
}

func evalSlideMacroImage(_ s: Slide) throws {
    let st = Date()
    let img = Data(s.fetchMacroJPEGImage()!)
    let et = Date()
    print("Macro image consumed \(et.timeIntervalSince(st) * 1000) ms")
    #expect(img.isJPEG)

    try img.write(
        to: URL(
            filePath: "\(s.name)_macro.jpg",
            directoryHint: .notDirectory,
            relativeTo: BASE))
}

func evalSlideThumbnailImage(_ s: Slide) throws {
    let st = Date()
    let jpg = s.fetchThumbnailJPEGImage(maxSize: 512)
    #expect(jpg != nil)
    guard let jpg else { return }
    let (w, h) = tjDecompressHeader(jpg)
    #expect(w <= 512 && h <= 512)
    let img = Data(jpg)
    let et = Date()
    print("Thumbnail image consumed \(et.timeIntervalSince(st) * 1000) ms")
    #expect(img.isJPEG)

    try img.write(
        to: URL(
            filePath: "\(s.name)_thumbnail.jpg",
            directoryHint: .notDirectory,
            relativeTo: BASE))
}

func evalSequenceTiles(_ s: Slide) -> (Int, Int) {
    var total = 0
    var totalSize = 0
    var cnt = 0
    let st = Date()
    for channel in 0..<s.channelCount {
        for tier in 0..<s.tierCount {
            for (li, layer) in s.layerTileSize.enumerated() {
                total += layer.r * layer.c
                for rw in 0..<layer.r {
                    for cl in 0..<layer.c {
                        let coord = TileCoordinate(
                            layer: li, row: rw, col: cl, tier: tier, channel: channel)
                        guard let raw = s.fetchTileImage(for: coord) else {
                            print("Tile at \(coord) is nil")
                            continue
                        }

                        let td = Data(raw)
                        if td.sameTileFormat(s) {
                            cnt += 1
                            totalSize += td.count
                        } else {
                            print("Tile at \(coord) expected \(s.tileTrait.compression)")
                            continue
                        }
                        // if li == s.layerTileSize.count - 1 {
                        //     try? td.write(to: URL(filePath: "tile_\(li)_\(rw)_\(cl).jpg",
                        //         directoryHint: .notDirectory,
                        //         relativeTo: BASE))
                        // }

                        if case .valid(trimming: true) = s.validate(coord) {
                            let (w, h) =
                                s.tileTrait.compression == .jpeg
                                ? tjDecompressHeader(raw) : pngDecompressHeader(raw)
                            #expect(w < s.tileTrait.size.w || h < s.tileTrait.size.h)
                        }
                    }
                }
            }
        }
    }
    let et = Date()
    let totalTime = et.timeIntervalSince(st)

    print("Sequence valid \(cnt) of \(total) tiles consumed \(totalTime) sec.")
    #expect(cnt > 0)
    print("Sequence average tile consumed \(totalTime * 1000 / Double(cnt)) ms")
    print("Sequence read speed \(Double(totalSize) / 1024 / 1024 / totalTime) MB/s")

    return (total, cnt)
}

func evalRandomTiles(_ s: Slide) -> (Int, Int) {
    var tiles: [TileCoordinate] = []
    for channel in 0..<s.channelCount {
        for tier in 0..<s.tierCount {
            for (li, layer) in s.layerTileSize.enumerated() {
                for rw in 0..<layer.r {
                    for cl in 0..<layer.c {
                        let coord = TileCoordinate(
                            layer: li, row: rw, col: cl, tier: tier, channel: channel)
                        tiles.append(coord)
                    }
                }
            }
        }
    }

    tiles = tiles.shuffled()
    var totalSize = 0
    var cnt = 0
    let st = Date()
    for coord in tiles {
        guard let td = s.fetchTileImage(for: coord) else { continue }
        if Data(td).isImage {
            cnt += 1
            totalSize += td.count

            // print("Fetched tile at \(coord.layer)-\(coord.row)-\(coord.col)")
        }
    }
    let et = Date()
    let totalTime = et.timeIntervalSince(st)

    print("Random valid \(cnt) of \(tiles.count) tiles consumed \(totalTime) sec.")
    #expect(cnt > 0)
    print("Random average tile consumed \(totalTime * 1000 / Double(cnt)) ms")
    print("Random read speed \(Double(totalSize) / 1024 / 1024 / totalTime) MB/s")

    return (tiles.count, cnt)
}

func evalVirtualTiles(_ s: Slide) throws {
    let tileW = Double(s.tileTrait.size.w)
    let tileH = Double(s.tileTrait.size.h)
    var width = s.layerImageSize.last?.w ?? 0
    var height = s.layerImageSize.last?.h ?? 0
    var layer = s.layerImageSize.count - 1

    var count = 0
    var missingCount = 0
    var totalSize = 0
    let st = Date()

    repeat {
        width = Int(ceil((Double(width) / Double(s.layerZoom))))
        height = Int(ceil((Double(height) / Double(s.layerZoom))))
        layer += 1

        for channel in 0..<s.channelCount {
            for tier in 0..<s.tierCount {
                for rw in 0..<(Int(ceil(Double(height) / tileH))) {
                    for cl in 0..<(Int(ceil(Double(width) / tileW))) {
                        let coord = TileCoordinate(
                            layer: layer, row: rw, col: cl, tier: tier, channel: channel)
                        guard let raw = s.fetchTileImage(for: coord), Data(raw).sameTileFormat(s)
                        else {
                            missingCount += 1
                            continue
                        }

                        let (w, h) =
                            s.tileTrait.compression == .jpeg
                            ? tjDecompressHeader(raw) : pngDecompressHeader(raw)
                        if w < Int(tileW) || h < Int(tileH) {
                            print("Virtual tile \(coord) size \(w) x \(h)")
                        }
                        #expect(w > 0 && h > 0)

                        count += 1
                        totalSize += raw.count

                        // try Data(raw).write(to: URL(filePath: "\(s.name)_\(layer)_\(rw)_\(cl).jpg",
                        //     directoryHint: .notDirectory,
                        //     relativeTo: BASE))
                    }
                }
            }
        }
    } while width > 1 || height > 1

    let et = Date()
    let totalTime = et.timeIntervalSince(st)

    print("Virtual valid \(count) tiles consumed \(totalTime) sec.")
    #expect(count > 0)
    print("Virtual average tile consumed \(totalTime * 1000 / Double(count)) ms")
    print("Virtual read speed \(Double(totalSize) / 1024 / 1024 / totalTime) MB/s")
    #expect(missingCount == 0)
}

extension Data {
    fileprivate func sameTileFormat(_ s: Slide) -> Bool {
        switch s.tileTrait.compression {
        case .jpeg:
            return isJPEG
        case .png:
            return isPNG
        default:
            return false
        }
    }
}
