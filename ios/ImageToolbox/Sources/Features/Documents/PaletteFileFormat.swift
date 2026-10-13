import Foundation
import ImageToolboxKit
import SwiftUI

/// The palette file formats the Palette tool reads and writes, with the coder of each one.
extension PaletteToolModel {
  /// The palette formats this build reads and writes. Each one uses the kit coder of the same name.
  /// Formats that share an extension are listed in the order they are tried when a file is opened.
  enum FileFormat: CaseIterable, Hashable, Sendable {
    case gimp
    case paintNET
    case corelPainter
    case paintShopPro
    case homesite
    case skencil
    case csv
    case hex
    case rgb
    case rgba
    case json
    case ase
    case aco
    case act
    case androidXML
    case scribus
    case openOffice
    case vga18
    case vga24
    case swift
    case kotlin
    case acb
    case corelPalette
    case corelDrawV3
    case riff
    case dcp
    case skp
    case sketch
    case swatchbooker
    case simplePalette
    case infinitePainter
    case procreate
    case autodeskColorBook
    case xara
    case affinity
    case krita
    case kOffice
    case clf
    case basicXML
    case corelDraw
    case svg
    case image

    /// The sections the pickers group the formats into.
    enum Family: CaseIterable, Sendable {
      case applications
      case text
      case adobe
      case xml
      case binary
      case image
      case vga
      case sourceCode

      /// The section header. Format names are proper nouns, so they are not part of this.
      var title: LocalizedStringKey {
        switch self {
        case .applications: "Application palettes"
        case .text: "Text"
        case .adobe: "Adobe"
        case .xml: "XML"
        case .binary: "Binary"
        case .image: "Image"
        case .vga: "VGA"
        case .sourceCode: "Source code"
        }
      }
    }

    /// What a format is called, the extensions it uses (the first one is the extension it is
    /// saved with), the picker section it is listed under and the kit coder that reads and writes
    /// it. Source code formats have no decoder, as in the Android app.
    private struct Spec: Sendable {
      let name: String
      let extensions: [String]
      let family: Family
      let decode: (@Sendable (Data) throws -> PaletteDocument)?
      let encode: @Sendable (PaletteDocument) -> Data
    }

    /// Reads a coder that keeps only the colours. The result has no palette name and no groups.
    private static func flatDecoder(
      _ decode: @escaping @Sendable (Data) throws -> [PaletteColour]
    ) -> @Sendable (Data) throws -> PaletteDocument {
      { data in PaletteDocument(colours: try decode(data)) }
    }

    /// Writes a coder that keeps only the colours, with the colours of the document in order.
    private static func flatEncoder(
      _ encode: @escaping @Sendable ([PaletteColour]) -> Data
    ) -> @Sendable (PaletteDocument) -> Data {
      { document in encode(document.allColours) }
    }

    /// The table of every format. Each case has exactly one entry.
    private static let specs: [FileFormat: Spec] = [
      .gimp: Spec(
        name: "GIMP (.gpl)", extensions: ["gpl"], family: .applications,
        decode: GIMPPaletteCoder.decodeDocument, encode: GIMPPaletteCoder.encodeDocument),
      .paintNET: Spec(
        name: "Paint.NET (.txt)", extensions: ["txt"], family: .applications,
        decode: PaintNETPaletteCoder.decodeDocument, encode: PaintNETPaletteCoder.encodeDocument),
      .corelPainter: Spec(
        name: "Corel Painter (.txt)", extensions: ["txt"], family: .applications,
        decode: flatDecoder(CorelPainterPaletteCoder.decode),
        encode: flatEncoder(CorelPainterPaletteCoder.encode)),
      .paintShopPro: Spec(
        name: "Paint Shop Pro (.pal)", extensions: ["pal", "psppalette"], family: .applications,
        decode: flatDecoder(PaintShopProPaletteCoder.decode),
        encode: flatEncoder(PaintShopProPaletteCoder.encode)),
      .homesite: Spec(
        name: "Homesite (.hpl)", extensions: ["hpl"], family: .applications,
        decode: flatDecoder(HPLPaletteCoder.decode), encode: flatEncoder(HPLPaletteCoder.encode)),
      .skencil: Spec(
        name: "Skencil (.spl)", extensions: ["spl"], family: .applications,
        decode: flatDecoder(SkencilPaletteCoder.decode),
        encode: flatEncoder(SkencilPaletteCoder.encode)),
      .csv: Spec(
        name: "CSV", extensions: ["csv"], family: .text,
        decode: flatDecoder(CSVPaletteCoder.decode), encode: flatEncoder(CSVPaletteCoder.encode)),
      .hex: Spec(
        name: "HEX (.hex)", extensions: ["hex"], family: .text,
        decode: flatDecoder(HEXPaletteCoder.decode), encode: flatEncoder(HEXPaletteCoder.encode)),
      .rgb: Spec(
        name: "RGB text (.rgb)", extensions: ["rgb", "txt"], family: .text,
        decode: flatDecoder(RGBPaletteCoder.decode), encode: flatEncoder(RGBPaletteCoder.encode)),
      .rgba: Spec(
        name: "RGBA text (.rgba)", extensions: ["rgba", "txt"], family: .text,
        decode: flatDecoder(RGBAPaletteCoder.decode), encode: flatEncoder(RGBAPaletteCoder.encode)),
      .json: Spec(
        name: "JSON", extensions: ["json", "jsoncolorpalette"], family: .text,
        decode: JSONPaletteCoder.decodeDocument, encode: JSONPaletteCoder.encodeDocument),
      .ase: Spec(
        name: "Adobe Swatch Exchange (.ase)", extensions: ["ase"], family: .adobe,
        decode: ASEPaletteCoder.decodeDocument, encode: ASEPaletteCoder.encodeDocument),
      .aco: Spec(
        name: "Adobe Photoshop (.aco)", extensions: ["aco"], family: .adobe,
        decode: flatDecoder(ACOPaletteCoder.decode), encode: flatEncoder(ACOPaletteCoder.encode)),
      .act: Spec(
        name: "Adobe Colour Table (.act)", extensions: ["act"], family: .adobe,
        decode: flatDecoder(ACTPaletteCoder.decode), encode: flatEncoder(ACTPaletteCoder.encode)),
      .androidXML: Spec(
        name: "Android colors (.xml)", extensions: ["xml"], family: .xml,
        decode: flatDecoder(AndroidColorsXMLPaletteCoder.decode),
        encode: flatEncoder(AndroidColorsXMLPaletteCoder.encode)),
      .scribus: Spec(
        name: "Scribus (.xml)", extensions: ["xml"], family: .xml,
        decode: ScribusXMLPaletteCoder.decodeDocument, encode: ScribusXMLPaletteCoder.encodeDocument
      ),
      .openOffice: Spec(
        name: "OpenOffice (.soc)", extensions: ["soc"], family: .xml,
        decode: flatDecoder(OpenOfficePaletteCoder.decode),
        encode: flatEncoder(OpenOfficePaletteCoder.encode)),
      .vga18: Spec(
        name: "VGA 18-bit (.vga18)", extensions: ["vga18"], family: .vga,
        decode: flatDecoder(VGA18BitPaletteCoder.decode),
        encode: flatEncoder(VGA18BitPaletteCoder.encode)),
      .vga24: Spec(
        name: "VGA 24-bit (.vga24)", extensions: ["vga24"], family: .vga,
        decode: flatDecoder(VGA24BitPaletteCoder.decode),
        encode: flatEncoder(VGA24BitPaletteCoder.encode)),
      .swift: Spec(
        name: "Swift (.swift)", extensions: ["swift"], family: .sourceCode,
        decode: nil, encode: SwiftPaletteCoder.encodeDocument),
      .kotlin: Spec(
        name: "Kotlin (.kt)", extensions: ["kt"], family: .sourceCode,
        decode: nil, encode: KotlinPaletteCoder.encodeDocument),
      .acb: Spec(
        name: "Adobe Colour Book (.acb)", extensions: ["acb"], family: .adobe,
        decode: ACBPaletteCoder.decodeDocument, encode: ACBPaletteCoder.encodeDocument),
      .corelPalette: Spec(
        name: "Corel Palette (.cpl)", extensions: ["cpl"], family: .applications,
        decode: CPLPaletteCoder.decodeDocument, encode: CPLPaletteCoder.encodeDocument),
      .corelDrawV3: Spec(
        name: "CorelDraw V3 (.pal)", extensions: ["pal"], family: .applications,
        decode: flatDecoder(CorelDraw3PaletteCoder.decode),
        encode: flatEncoder(CorelDraw3PaletteCoder.encode)),
      .riff: Spec(
        name: "Microsoft RIFF (.pal)", extensions: ["pal"], family: .binary,
        decode: flatDecoder(RIFFPaletteCoder.decode), encode: flatEncoder(RIFFPaletteCoder.encode)),
      .dcp: Spec(
        name: "ColorPaletteCodable (.dcp)", extensions: ["dcp"], family: .binary,
        decode: DCPPaletteCoder.decodeDocument, encode: DCPPaletteCoder.encodeDocument),
      .skp: Spec(
        name: "SKP (.skp)", extensions: ["skp"], family: .binary,
        decode: SKPPaletteCoder.decodeDocument, encode: SKPPaletteCoder.encodeDocument),
      .sketch: Spec(
        name: "Sketch (.sketchpalette)", extensions: ["sketchpalette"], family: .applications,
        decode: flatDecoder(SketchPaletteCoder.decode),
        encode: flatEncoder(SketchPaletteCoder.encode)),
      .swatchbooker: Spec(
        name: "Swatchbooker (.sbz)", extensions: ["sbz"], family: .applications,
        decode: SwatchbookerPaletteCoder.decodeDocument,
        encode: SwatchbookerPaletteCoder.encodeDocument),
      .simplePalette: Spec(
        name: "Simple Palette (.color-palette)", extensions: ["color-palette"],
        family: .applications,
        decode: SimplePaletteCoder.decodeDocument, encode: SimplePaletteCoder.encodeDocument),
      .infinitePainter: Spec(
        name: "Infinite Painter (.clrs)", extensions: ["clrs"], family: .applications,
        decode: InfinitePainterPaletteCoder.decodeDocument,
        encode: InfinitePainterPaletteCoder.encodeDocument),
      .procreate: Spec(
        name: "Procreate (.swatches)", extensions: ["swatches"], family: .applications,
        decode: ProcreateSwatchesPaletteCoder.decodeDocument,
        encode: ProcreateSwatchesPaletteCoder.encodeDocument),
      .autodeskColorBook: Spec(
        name: "Autodesk Colour Book (.acb)", extensions: ["acb"], family: .applications,
        decode: AutodeskColorBookPaletteCoder.decodeDocument,
        encode: AutodeskColorBookPaletteCoder.encodeDocument),
      .xara: Spec(
        name: "Xara (.jcw)", extensions: ["jcw"], family: .applications,
        decode: flatDecoder(JCWPaletteCoder.decode), encode: flatEncoder(JCWPaletteCoder.encode)),
      .affinity: Spec(
        name: "Affinity Designer (.afpalette)", extensions: ["afpalette"], family: .applications,
        decode: AFPaletteCoder.decodeDocument, encode: AFPaletteCoder.encodeDocument),
      .krita: Spec(
        name: "Krita (.kpl)", extensions: ["kpl"], family: .applications,
        decode: KRITAPaletteCoder.decodeDocument, encode: KRITAPaletteCoder.encodeDocument),
      .kOffice: Spec(
        name: "KOffice (.colors)", extensions: ["colors"], family: .applications,
        decode: flatDecoder(KOfficePaletteCoder.decode),
        encode: flatEncoder(KOfficePaletteCoder.encode)),
      .clf: Spec(
        name: "CLF (.clf)", extensions: ["clf"], family: .text,
        decode: flatDecoder(CLFPaletteCoder.decode), encode: flatEncoder(CLFPaletteCoder.encode)),
      .basicXML: Spec(
        name: "Basic XML (.xml)", extensions: ["xml"], family: .xml,
        decode: BasicXMLPaletteCoder.decodeDocument, encode: BasicXMLPaletteCoder.encodeDocument),
      .corelDraw: Spec(
        name: "CorelDraw XML (.xml)", extensions: ["xml"], family: .xml,
        decode: CorelXMLPaletteCoder.decodeDocument, encode: CorelXMLPaletteCoder.encodeDocument),
      .svg: Spec(
        name: "SVG (.svg)", extensions: ["svg"], family: .xml,
        decode: flatDecoder(SVGPaletteCoder.decode), encode: flatEncoder(SVGPaletteCoder.encode)),
      .image: Spec(
        name: "Image swatches (.png)", extensions: ["png", "jpg", "jpeg"], family: .image,
        decode: flatDecoder(ImagePaletteCoder.decode), encode: flatEncoder(ImagePaletteCoder.encode)
      ),
    ]

    private var spec: Spec {
      guard let spec = Self.specs[self] else { preconditionFailure("No spec for \(self)") }
      return spec
    }

    /// Whether the kit has a decoder for this format, so the Read as picker offers it.
    var isReadable: Bool { spec.decode != nil }

    /// Whether the kit has an encoder for this format, so the Write as picker offers it. Every
    /// format has one.
    var isWritable: Bool { true }

    /// The extension the format is saved with, without the dot.
    var fileExtension: String { spec.extensions[0] }

    /// The name in the pickers. Format names are proper nouns, so they are not translated.
    var name: String { spec.name }

    /// The picker section this format is listed under.
    var family: Family { spec.family }

    /// The readable formats that the extension of `fileName` can mean, in the order they are
    /// tried. The extension is compared ignoring case, and an unknown extension gives no formats.
    static func readableFormats(forFileName fileName: String) -> [FileFormat] {
      let extensionName = (fileName as NSString).pathExtension.lowercased()
      return allCases.filter { $0.isReadable && $0.spec.extensions.contains(extensionName) }
    }

    func decode(_ data: Data) throws -> PaletteDocument {
      guard let decode = spec.decode else {
        // Write-only, so the Read as picker never selects these. Nothing can be read from them.
        throw PaletteFormatError.invalidFormat
      }
      return try decode(data)
    }

    func encode(_ document: PaletteDocument) -> Data {
      spec.encode(document)
    }
  }
}
