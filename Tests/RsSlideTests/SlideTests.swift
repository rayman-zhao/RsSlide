import Foundation
import Testing
import LibJPEGTurbo
import LibTIFF
import RsSlide

@Suite
struct SlideTests {
    init() async {
        await TIFFSetWarningHanlder { md, msg in
            // print("TIFFWarning: \(md) - \(msg)")
        }
    }

    @Test(.serialized, arguments: [
        ("志盈/60637.svs", "8495DB07-A11A-55C5-B606-AAFAB29BF4D6", "60637", "SVS", true, true, false),
        ("SVS/125870-2022;1C_20220926112546.svs", "33D0CE0D-3A5F-55B6-BF87-F47841EE52A5", "125870-2022;1C_20220926112546", "SVS", true, true, false),
        ("SVS/2312399.svs", "9F23270E-E03B-5F9D-9D85-136835176D09", "2312399", "SVS", false, true, false),
        ("KFB/1021754 (2).tif", "EFD73D09-4D58-517D-8E50-D59FDA53F7A0", "1021754 (2)", "TIF", true, true, false),
        ("MDS/6横纹肌肉瘤/", "D1C530A6-EE7F-47BD-B2E6-766EC973742D", "6横纹肌肉瘤", "MDS", false, false, true),
        ("MDS/7多形性脂肪肉瘤/1.mds", "A7D41B1D-0B0F-49AB-83DE-DA25ADE91231", "7多形性脂肪肉瘤", "MDS", false, false, true),
        ("MDS/19.1_20160414_1904236501_2/1.mds", "6adb43b1-49bb-4992-8a30-5eef1352dc9e", "19.1_20160414_1904236501_2", "MDS", true, true, true),
        ("MDS/114504/", "509f235d-099a-40aa-a56f-eb96d82ae372", "114504", "MDS", false, false, true),
        ("MDS/0002/", "A159D05B-ADE7-4FBA-B344-DA6E1BE33102", "0002", "MDS", false, true, true),
        ("MDS/BW20200014/", "7A25F880-7BC2-44BA-8362-8E82EC70A6BF", "BW20200014", "MDS", true, true, true),
    ])
    func slideValid(_ fn: String, _ sid: String, _ name: String, _ fmt: String, _ label: Bool, _ macro: Bool, _ more: Bool) async throws {
        let trait = URL(filePath: fn, relativeTo: BASE).slideTrait
        if more && (trait == .isGenericFile || trait == .isGenericFolder) {
            return
        }

        print("Validating \(fn)")
        let s = try #require(evalMakeSlide(fromTrait: trait))
        #expect(s.id == UUID(uuidString: sid))
        #expect(s.name == name)
        #expect(s.format == fmt)
        await evalSlideMetadata(s)
        #expect(throws: Never.self) {
            if label {
                try evalSlideLabelImage(s)
            } else {
                #expect(s.fetchLabelJPEGImage().isEmpty)
            }
            if macro {
                try evalSlideMacroImage(s)
            } else {
                #expect(s.fetchMacroJPEGImage().isEmpty)
            }
            try evalSlideThumbnailImage(s)
        }
        #expect(evalSequenceTiles(s) == evalRandomTiles(s))
        evalNonExistingTiles(s)
    }
}

func evalMakeSlide(fromTrait trait: SlideTrait) -> Slide? {
    guard case .isSlide(let builder) = trait else { fatalError() }

    let st = Date()
    let s =  builder.makeView()
    let et = Date()
    print("Open consumed \(et.timeIntervalSince(st) * 1000) ms")
    return s
}

actor ExstingId {
    private var all: Set<UUID> = []

    func insertNew(_ item: UUID) -> Int {
        let cnt = all.count
        all.insert(item)
        return all.count - cnt
    }
}

let allIds = ExstingId()

func evalSlideMetadata(_ s: Slide) async {
    #expect(await allIds.insertNew(s.id) == 1)
    print("Slide GUID \(s.id)")
    
    #expect(s.dataSize > 0)
    print("File size \(s.dataSize)")
    
    #expect([10, 20, 40].contains(s.scanObjective))
    print("Scan objective \(s.scanObjective)")
    
    #expect(0.001...1 ~= s.scanScale )
    print("Scan scale \(s.scanScale)")
    
    #expect(s.tileTrait.size > (0, 0))
    print("Tile size \(s.tileTrait.size.w) x \(s.tileTrait.size.h)")
    #expect([24, 8].contains(s.tileTrait.sampleBits * s.tileTrait.pixelFormat.rawValue))
    #expect(s.tileTrait.maxBytes == s.tileTrait.size.w * s.tileTrait.size.h * 3)
    print("Tile format \(s.tileTrait)")
    
    #expect(s.layerImageSize.count == s.layerTileSize.count)
    #expect(s.layerImageSize.count > 0)
    for i in 0..<s.layerImageSize.count {
        print("Layer \(i) \(s.layerImageSize[i].w)-\(s.layerImageSize[i].h) in \(s.layerTileSize[i].r)-\(s.layerTileSize[i].c)")
        
        if i > 0 {
            #expect(s.layerImageSize[i - 1].w / s.layerZoom == s.layerImageSize[i].w)
            #expect(s.layerImageSize[i - 1].h / s.layerZoom == s.layerImageSize[i].h)
            #expect(s.layerTileSize[i - 1].r / s.layerZoom <= (s.layerTileSize[i].r + 1))
            #expect(s.layerTileSize[i - 1].c / s.layerZoom <= (s.layerTileSize[i].c + 1))
        }
    }
    
    #expect([2, 4].contains(s.layerZoom))
    print("Layer zoom \(s.layerZoom)")
}

func evalSlideLabelImage(_ s: Slide) throws {
    let st = Date()
    let img = Data(s.fetchLabelJPEGImage())
    let et = Date()
    print("Label image consumed \(et.timeIntervalSince(st) * 1000) ms")
    #expect(img.isJPEG)
    
    try img.write(to: URL(filePath: "\(s.name)_label.jpg",
                          directoryHint: .notDirectory,
                          relativeTo: BASE))
}

func evalSlideMacroImage(_ s: Slide) throws {
    let st = Date()
    let img = Data(s.fetchMacroJPEGImage())
    let et = Date()
    print("Macro image consumed \(et.timeIntervalSince(st) * 1000) ms")
    #expect(img.isJPEG)
    
    try img.write(to: URL(filePath: "\(s.name)_macro.jpg",
                          directoryHint: .notDirectory,
                          relativeTo: BASE))
}

func evalSlideThumbnailImage(_ s: Slide) throws {
    let st = Date()
    let jpg = s.fetchThumbnailJPEGImage(with: 512)
    let (w, h) = tjDecompressHeader(jpg)
    #expect(w <= 512 && h <= 512)
    let img = Data(jpg)
    let et = Date()
    print("Thumbnail image consumed \(et.timeIntervalSince(st) * 1000) ms")
    #expect(img.isJPEG)
    
    try img.write(to: URL(filePath: "\(s.name)_thumbnail.jpg",
                          directoryHint: .notDirectory,
                          relativeTo: BASE))
}

func evalSequenceTiles(_ s: Slide) -> (Int, Int) {
    var total = 0, totalSize = 0
    var cnt = 0
    let st = Date()
    for _ in 0..<s.tierCount {
        for (li, layer) in s.layerTileSize.enumerated() {
            total += layer.r * layer.c
            for rw in 0..<layer.r {
                for cl in 0..<layer.c {
                    let coord = TileCoordinate(layer: li, row: rw, col: cl)
                    let td = Data(s.fetchTileRawImage(at: coord))
                    if td.isImage {
                        cnt += 1
                        totalSize += td.count                  
                    }
                    // if li == s.layerTileSize.count - 1 {
                    //     try? td.write(to: URL(filePath: "tile_\(li)_\(rw)_\(cl).jpg",
                    //         directoryHint: .notDirectory,
                    //         relativeTo: BASE))
                    // }
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
    for _ in 0..<s.tierCount {
        for (li, layer) in s.layerTileSize.enumerated() {
            for rw in 0..<layer.r {
                for cl in 0..<layer.c {
                    let coord = TileCoordinate(layer: li, row: rw, col: cl)
                    tiles.append(coord)
                }
            }
        }
    }
    
    tiles = tiles.shuffled()
    var totalSize = 0
    var cnt = 0 
    let st = Date()
    for coord in tiles {
        let td = Data(s.fetchTileRawImage(at: coord))
        if td.isImage{
            cnt += 1
            totalSize += td.count
            
            //print("Fetched tile at \(coord.layer)-\(coord.row)-\(coord.col)")
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

func evalNonExistingTiles(_ s: Slide) {
    var width = s.layerImageSize.last?.w ?? 0
    var height = s.layerImageSize.last?.h ?? 0
    var layer = s.layerImageSize.count - 1
    var cnt = 0

    while width > 0 || height > 0 {
        layer += 1
        width /= s.layerZoom
        height /= s.layerZoom

        for rw in 0..<(height / s.tileTrait.size.h + 1) {
            for cl in 0..<(width / s.tileTrait.size.w + 1) {
                let coord = TileCoordinate(layer: layer, row: rw, col: cl)
                let td = s.fetchTileRawImage(at: coord)
                #expect(td.count == 0)

                cnt += 1
            }
        }
    }

    #expect(cnt > 0)
}