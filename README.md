# RsSlide

WSI digital slide file parser — a Swift library for detecting, opening, and converting whole-slide imaging files. Platforms: macOS 15+ and Windows (Swift 6.4 toolchain).

## Supported formats

| Extension(s) | Format | Provider |
|---|---|---|
| `.svs`, `.tif`, `.tiff` | Aperio SVS / generic TIFF pyramid | `SVS` |
| `.ome.tif`, `.ome.tiff` | OME-TIFF | `OMETIFF` |
| `.qptiff` | PerkinElmer QPTIFF | `QPTIFF` |
| `.dcm` | DICOM WSI (SQRAY) | `DCM` |
| `.csp` | CSP (vendor SDK DLL, Windows) | `CSP` |

Directories are inspected as well: folders are classified as slide folders (by their payload files), metadata folders, or generic folders.

## Usage

```swift
import RsSlide

switch url.slideKind {
case .slide(let factory):
    let preview = factory.makePreview()          // cheap: metadata + macro image
    let macro = preview.fetchMacroJPEGImage()

    if let slide = factory.makeSlide() {         // full parse
        let size = slide.layerImageSize[0]       // base layer dimensions
        let raw = slide.fetchTileRawImage(
            for: TileCoordinate(layer: 0, row: 0, col: 0))  // compressed tile bytes
    }
default:
    break   // .metadataFolder, .genericFolder, .genericFile, .notSupported
}
```

`Slide` exposes metadata (`name`, `format`, `dataSize`, `scanObjective`, `scanScale`, `extendedXML`, `id`), pyramid geometry (`layerImageSize`, `layerTileSize`, `layerZoom`), stain channels (`channelTrait`), tile format (`tileTrait`), label/macro images, and raw tile access. Tiles are passed through in their stored compression (JPEG/PNG/JXL per `tileTrait.compression`) — decode with LibJPEGTurbo/LibPNG or your own pipeline.

Export:

```swift
try slide.convert(to: out.appending(path: "out.svs"))
try slide.crop(to: out.appending(path: "macro.jpg"))          // full image
try slide.crop(rect: rect, to: out.appending(path: "roi.tif")) // region
```

## Building

```bash
git clone https://github.com/rayman-zhao/RsSlide
cd RsSlide
swift build
```

Remote URL dependencies (`.package(url:)`) are not supported yet — reference RsSlide via a local path (`.package(path:)`) for now.

The CSP provider loads a vendor DLL at runtime (`Sources/RsSlide/DLLLoader.swift`). The DLL is searched in the main bundle's resource subdirectory or next to the loaded module; ship it with your app accordingly.

## Testing

The test suites are data-driven over a local corpus of slide files, which is not part of this repository — they cannot be run from a public checkout.

## Project layout

```
Sources/RsSlide/          Core: Slide, SlidePreview, SlideKind, SlideFileInfo, export
Sources/RsSlide/Providers Format providers (SVS, OMETIFF, QPTIFF, DCM, CSP)
Sources/RsSlide/Export    SVS/TIFF/JPEG conversion backends
Sources/CVendorSDKs       Vendor SDK C headers + module map
Tests/RsSlideTests        Data-driven test suites (require a local slide corpus)
```

Dependencies: [RsFoundation](https://github.com/rayman-zhao/RsFoundation), [RsPack](https://github.com/rayman-zhao/RsPack) (libjpeg-turbo, libpng, libtiff, etc.).
