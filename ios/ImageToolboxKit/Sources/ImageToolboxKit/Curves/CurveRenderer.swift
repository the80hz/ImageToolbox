import CoreGraphics
import Foundation

/// Applies a set of adjustments to every pixel, stage by stage in the order of `CurveAdjustments`.
/// All stages act on straight (unpremultiplied) colour, so a semi-transparent pixel keeps its hue,
/// and its alpha is copied.
public enum CurveRenderer {

  public static func apply(_ image: CGImage, adjustments: CurveAdjustments) -> CGImage? {
    guard let raster = RasterImage(image) else { return nil }
    return apply(raster, adjustments: adjustments).toCGImage()
  }

  /// Applies the RGB curves, the colour wheels and the hue, saturation and value curves.
  public static func apply(
    _ image: CGImage, curves: CurveSet, relations: RelationCurves = RelationCurves(),
    wheels: ColorWheels = .identity
  ) -> CGImage? {
    apply(
      image,
      adjustments: CurveAdjustments(curves: curves, relations: relations, wheels: wheels))
  }

  public static func apply(
    _ raster: RasterImage, curves: CurveSet, relations: RelationCurves = RelationCurves(),
    wheels: ColorWheels = .identity
  ) -> RasterImage {
    apply(
      raster,
      adjustments: CurveAdjustments(curves: curves, relations: relations, wheels: wheels))
  }

  public static func apply(_ raster: RasterImage, adjustments: CurveAdjustments) -> RasterImage {
    let tables = adjustments.curves.lookupTables()
    let cmyk = adjustments.cmyk.isIdentity ? nil : CMYKTransform(adjustments.cmyk)
    let lab = adjustments.lab.isIdentity ? nil : LabTransform(adjustments.lab)
    let changes = adjustments.relations.changeTables()
    let balances = adjustments.wheels.isIdentity ? nil : adjustments.wheels.balances()
    let straight = raster.straightRGBA()
    var output = [UInt8](repeating: 0, count: straight.count)
    var index = 0
    while index < straight.count {
      var red = Double(tables.red[Int(straight[index])]) / 255
      var green = Double(tables.green[Int(straight[index + 1])]) / 255
      var blue = Double(tables.blue[Int(straight[index + 2])]) / 255

      if let cmyk {
        (red, green, blue) = cmyk.apply(red: red, green: green, blue: blue)
      }

      if let lab {
        (red, green, blue) = lab.apply(red: red, green: green, blue: blue)
      }

      if !changes.isEmpty {
        var hsv = RelationAdjuster.toHSV(red: red, green: green, blue: blue)
        for change in changes {
          let level = Int((RelationAdjuster.input(of: hsv, for: change.kind) * 255).rounded())
          let clamped = min(max(level, 0), 255)
          hsv = RelationAdjuster.adjust(hsv, kind: change.kind, change: change.table[clamped])
        }
        let rgb = RelationAdjuster.toRGB(hsv)
        red = min(max(rgb.red, 0), 1)
        green = min(max(rgb.green, 0), 1)
        blue = min(max(rgb.blue, 0), 1)
      }

      if let balances {
        let adjusted = adjustments.wheels.adjusted(
          red: red, green: green, blue: blue, balances: balances)
        red = adjusted.red
        green = adjusted.green
        blue = adjusted.blue
      }

      let alpha = raster.pixels[index + 3]
      output[index] = premultiplied(UInt8((red * 255).rounded()), alpha)
      output[index + 1] = premultiplied(UInt8((green * 255).rounded()), alpha)
      output[index + 2] = premultiplied(UInt8((blue * 255).rounded()), alpha)
      output[index + 3] = alpha
      index += 4
    }
    return RasterImage(width: raster.width, height: raster.height, pixels: output)
  }

  private static func premultiplied(_ value: UInt8, _ alpha: UInt8) -> UInt8 {
    UInt8((Int(value) * Int(alpha) + 127) / 255)
  }
}
