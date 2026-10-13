import CoreGraphics
import Foundation

/// A named paper size in PDF points, 72 to the inch, in portrait.
public struct PDFPageSize: Hashable, Sendable, Identifiable {
  public let name: String
  public let width: Double
  public let height: Double

  public var id: String { name }
  public var size: CGSize { CGSize(width: width, height: height) }

  public init(name: String, width: Double, height: Double) {
    self.name = name
    self.width = width
    self.height = height
  }

  /// The same size turned on its side.
  public var landscape: PDFPageSize { PDFPageSize(name: name, width: height, height: width) }

  public static let a4 = PDFPageSize(name: "A4", width: 595, height: 842)
  public static let letter = PDFPageSize(name: "Letter", width: 612, height: 792)

  /// The sizes a person can choose from: ISO A and B series, US sizes, photo prints and a few
  /// others. They are the same sizes the Android app lists.
  public static let all: [PDFPageSize] = [
    PDFPageSize(name: "A0", width: 2384, height: 3370),
    PDFPageSize(name: "A1", width: 1684, height: 2384),
    PDFPageSize(name: "A2", width: 1191, height: 1684),
    PDFPageSize(name: "A3", width: 842, height: 1191),
    a4,
    PDFPageSize(name: "A5", width: 420, height: 595),
    PDFPageSize(name: "A6", width: 297, height: 420),
    PDFPageSize(name: "A7", width: 210, height: 297),
    PDFPageSize(name: "A8", width: 148, height: 210),
    PDFPageSize(name: "B0", width: 2835, height: 4008),
    PDFPageSize(name: "B1", width: 2004, height: 2835),
    PDFPageSize(name: "B2", width: 1417, height: 2004),
    PDFPageSize(name: "B3", width: 1001, height: 1417),
    PDFPageSize(name: "B4", width: 709, height: 1001),
    PDFPageSize(name: "B5", width: 499, height: 709),
    PDFPageSize(name: "B6", width: 354, height: 499),
    PDFPageSize(name: "C4", width: 649, height: 918),
    PDFPageSize(name: "C5", width: 459, height: 649),
    PDFPageSize(name: "C6", width: 323, height: 459),
    PDFPageSize(name: "DL", width: 461, height: 648),
    letter,
    PDFPageSize(name: "Legal", width: 612, height: 1008),
    PDFPageSize(name: "Tabloid", width: 792, height: 1224),
    PDFPageSize(name: "Statement", width: 396, height: 612),
    PDFPageSize(name: "Executive", width: 522, height: 756),
    PDFPageSize(name: "Photo 4x6", width: 288, height: 432),
    PDFPageSize(name: "Photo 5x7", width: 360, height: 504),
    PDFPageSize(name: "Photo 8x10", width: 576, height: 720),
    PDFPageSize(name: "Photo 12x18", width: 864, height: 1296),
    PDFPageSize(name: "Index card 3x5", width: 216, height: 360),
    PDFPageSize(name: "Square 15 cm", width: 425, height: 425),
    PDFPageSize(name: "Square 21 cm", width: 595, height: 595),
  ]
}
