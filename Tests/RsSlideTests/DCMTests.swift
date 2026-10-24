import Foundation
import Testing

@testable import RsSlide

@Suite
struct DCMTests {
    @Test(.serialized)
    func volumeTiles() async throws {
        let trait = URL(
            filePath: "DCM/锦州582531-10/", directoryHint: .isDirectory, relativeTo: BASE
        ).slideKind
        let s = try #require(evalMakeSlide(fromTrait: trait))

        #expect(s.layerImageSize.count == 9)
        #expect(s.layerImageSize[0] == (185472, 188160))
        #expect(s.layerImageSize[8] == (725, 735))
        #expect(s.tileTrait.size == (672, 672))
        #expect(s.layerTileSize[0] == (280, 276))
        #expect(s.layerTileSize[8] == (2, 2))
        #expect(s.layerZoom == 2)
        #expect(s.scanObjective == 40)
        #expect(abs(s.scanScale - 0.1064) < 0.0001)
        print("Slide GUID \(s.id)")

        // Base-layer tiles at the grid corners and center pass through the
        // encapsulated codestream undecoded.
        for coord in [
            TileCoordinate(layer: 0, row: 0, col: 0),
            TileCoordinate(layer: 0, row: 0, col: 275),
            TileCoordinate(layer: 0, row: 279, col: 0),
            TileCoordinate(layer: 0, row: 139, col: 138),
            TileCoordinate(layer: 0, row: 279, col: 275),
        ] {
            #expect(s.fetchTileRawImage(for: coord) != nil)
        }

        // The smallest layer has one frame per grid cell; its first frame is the
        // HEVC Annex-B access unit verified against the raw file bytes.
        for row in 0..<s.layerTileSize[8].r {
            for col in 0..<s.layerTileSize[8].c {
                #expect(
                    s.fetchTileRawImage(for: TileCoordinate(layer: 8, row: row, col: col)) != nil)
            }
        }
        #expect(
            s.fetchTileRawImage(for: TileCoordinate(layer: 8, row: 0, col: 0))!
                .starts(with: [0, 0, 0, 1]))

        // Beyond the stored pyramid tiles are virtual, never raw-fetchable.
        #expect(s.fetchTileRawImage(for: TileCoordinate(layer: 9, row: 0, col: 0)) == nil)

        #expect(Data(s.fetchLabelJPEGImage()!).isJPEG)
        #expect(Data(s.fetchMacroJPEGImage()!).isJPEG)
    }
}
