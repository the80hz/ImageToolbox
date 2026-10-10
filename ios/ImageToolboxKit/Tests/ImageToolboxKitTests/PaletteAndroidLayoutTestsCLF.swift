import Foundation
import Testing

@testable import ImageToolboxKit

// Byte layout of the CLF (Lab colours) text written by the Android coder. Each line is the name,
// then L, a and b, separated by tabs. The lines are joined by "\n", with no line break at the end.
// The Lab values are those of ColorUtils.colorToLAB for each 8-bit colour, evaluated in double
// precision in the same order as the androidx code, and printed the way java.lang.Double.toString
// prints them: plain notation from 1e-3 up to 1e7, and "E" notation outside that range.

@Suite("Android layout: CLF (Lab colours)")
struct PaletteAndroidLayoutTestsCLF {

  /// The colours written by the test. The colours without a name get "Color" from the writer.
  private static let colours: [PaletteColour] = [
    PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
    PaletteColour(name: "Green", red: 0, green: 255, blue: 0),
    PaletteColour(name: "Blue", red: 0, green: 0, blue: 255),
    PaletteColour(name: "Accent", red: 64, green: 128, blue: 191),
    PaletteColour(red: 0, green: 0, blue: 0),
    PaletteColour(red: 255, green: 255, blue: 255),
    PaletteColour(red: 1, green: 1, blue: 1),
    PaletteColour(red: 3, green: 2, blue: 1),
  ]

  /// The Android writer output for `colours`. The last three lines have "E" notation values.
  private static let androidText = [
    "Red\t53.23288178584245\t80.10930952982204\t67.22006831026425",
    "Green\t87.73703347354422\t-86.18463649762525\t83.18116474777854",
    "Blue\t32.302586667249486\t79.19666178930935\t-107.86368104495168",
    "Accent\t52.16342934252542\t-0.24124707424971747\t-39.000405116622794",
    "Color\t0.0\t0.0\t0.0",
    "Color\t100.0\t0.00526049995830391\t-0.010408184525267927",
    "Color\t0.27417592423966397\t3.730131757639921E-5\t-7.380574454374234E-5",
    "Color\t0.5868461482425786\t0.12249008154339991\t0.47050369037209827",
  ].joined(separator: "\n")

  /// The colours that the Android reader gets from `androidText`, with the 8-bit values that
  /// `ColorUtils.LABToColor` rounds to.
  private static let readBack: [PaletteColour] = [
    PaletteColour(name: "Red", red: 255, green: 0, blue: 0),
    PaletteColour(name: "Green", red: 0, green: 255, blue: 0),
    PaletteColour(name: "Blue", red: 0, green: 0, blue: 255),
    PaletteColour(name: "Accent", red: 64, green: 128, blue: 191),
    PaletteColour(name: "Color", red: 0, green: 0, blue: 0),
    PaletteColour(name: "Color", red: 255, green: 255, blue: 255),
    PaletteColour(name: "Color", red: 1, green: 1, blue: 1),
    PaletteColour(name: "Color", red: 3, green: 2, blue: 1),
  ]

  @Test("CLF writer matches the Android text byte for byte, including Double.toString digits")
  func clfWriterBytes() {
    let data = CLFPaletteCoder.encode(Self.colours)
    #expect(Array(data) == Array(Self.androidText.utf8))
  }

  @Test("CLF reader takes the Android text and gives back the 8-bit colours")
  func clfReaderOnAndroidText() throws {
    let colours = try CLFPaletteCoder.decode(Data(Self.androidText.utf8))
    #expect(colours == Self.readBack)
  }

  @Test("CLF writer keeps names as they are, with tabs and line breaks written as spaces")
  func clfNames() {
    let data = CLFPaletteCoder.encode([
      PaletteColour(name: " A\tB\nC ", red: 0, green: 0, blue: 0)
    ])
    #expect(Array(data) == Array(" A B C \t0.0\t0.0\t0.0".utf8))
  }
}
