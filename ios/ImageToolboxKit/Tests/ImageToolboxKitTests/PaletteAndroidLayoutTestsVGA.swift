import Foundation
import Testing

@testable import ImageToolboxKit

// Byte layouts of the VGA palettes and the Swift and Kotlin source exports, checked against the
// Android coders.

@Suite("Android layout: VGA palettes and the Swift and Kotlin exports")
struct PaletteAndroidLayoutTestsVGA {

  @Test("VGA 18-bit writer scales channels to 6 bits with round to nearest")
  func vga18WriterLayout() {
    let data = VGA18BitPaletteCoder.encode([PaletteColour(red: 255, green: 0, blue: 128)])
    #expect(Array(data) == [63, 0, 32])
  }

  @Test("VGA 18-bit writer keeps the name positions of the names header")
  func vga18NamesHeader() {
    let data = VGA18BitPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 0, green: 0, blue: 0),
      PaletteColour(name: "Blue", red: 0, green: 0, blue: 255),
    ])
    let header = Array("; Names: Red, , Blue\n".utf8)
    #expect(Array(data.prefix(header.count)) == header)
    #expect(Array(data.dropFirst(header.count)) == [63, 0, 0, 0, 0, 0, 0, 0, 63])
  }

  @Test("VGA 18-bit reader reads an Android names header and rejects channels above 63")
  func vga18ReaderOnAndroidBytes() throws {
    let file: [UInt8] = Array("; Names: Red, Blue\n".utf8) + [63, 0, 0, 0, 0, 63]
    let colours = try VGA18BitPaletteCoder.decode(Data(file))
    #expect(
      colours == [
        PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
        PaletteColour(name: "Blue", red: 0, green: 0, blue: 255),
      ])
    #expect(throws: PaletteFormatError.invalidFormat) {
      try VGA18BitPaletteCoder.decode(Data([64, 0, 0]))
    }
  }

  @Test("VGA 24-bit writer writes the bytes as they are, after a names header when named")
  func vga24WriterLayout() {
    #expect(
      Array(VGA24BitPaletteCoder.encode([PaletteColour(red: 1, green: 2, blue: 3)])) == [1, 2, 3])
    let named = VGA24BitPaletteCoder.encode([PaletteColour(name: "X", red: 9, green: 8, blue: 7)])
    #expect(Array(named) == Array("; Names: X\n".utf8) + [9, 8, 7])
  }

  @Test("VGA 24-bit reader takes the names header of the Android writer")
  func vga24ReaderOnAndroidBytes() throws {
    let file: [UInt8] = Array("; Names: X\n".utf8) + [9, 8, 7]
    #expect(
      try VGA24BitPaletteCoder.decode(Data(file))
        == [PaletteColour(name: "X", red: 9, green: 8, blue: 7)])
  }

  @Test("Swift export writes the colour literals, four decimals and the name comments")
  func swiftExportLayout() {
    let data = SwiftPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 0, green: 128, blue: 255, alpha: 128),
    ])
    let expected =
      "struct ExportedPalettes {\n"
      + "   // Group (global)\n"
      + "   static let group0: [CGColor] = [\n"
      + "      #colorLiteral(red: 1.0000, green: 0.0000, blue: 0.0000, alpha: 1.0000), // Red"
      + " #colorLiteral(red: 0.0000, green: 0.5020, blue: 1.0000, alpha: 0.5020),\n"
      + "   ]\n\n"
      + "}\n"
    #expect(Array(data) == Array(expected.utf8))
  }

  @Test("Kotlin export writes Color(0xAARRGGBB) constants, names and the three lists")
  func kotlinExportLayout() {
    let data = KotlinPaletteCoder.encode([
      PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
      PaletteColour(red: 0, green: 128, blue: 255, alpha: 128),
    ])
    let expected =
      "package palette\n\n"
      + "import androidx.compose.ui.graphics.Color\n\n"
      + "/**\n * Exported palette: Untitled\n * Total colors: 2\n */\n"
      + "object ExportedPalette {\n\n"
      + "    // Individual color constants\n"
      + "    val Red: Color = Color(0xFFFF0000)\n"
      + "    val color1: Color = Color(0x800080FF)\n\n"
      + "    // Group: global\n"
      + "    val group0: List<Color> = listOf(\n"
      + "        Color(0xFFFF0000),\n"
      + "        Color(0x800080FF)\n"
      + "    )\n\n"
      + "    /**\n"
      + "     * All colors from all groups\n"
      + "     */\n"
      + "    val allColors: List<Color> = listOf(\n"
      + "        Color(0xFFFF0000),\n"
      + "        Color(0x800080FF)\n"
      + "    )\n"
      + "}\n"
    #expect(String(decoding: data, as: UTF8.self) == expected)
  }
}
