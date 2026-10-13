import CoreGraphics
import ImageToolboxKit
import Observation
import SwiftUI

@MainActor
@Observable
final class FractalToolModel {
  // Every value below changes the picture, so each change bumps `revision`. Changing the kind also
  // puts the view, the constants and the exponent back to that kind's Android defaults.
  var kind = EscapeTimeFractal.Kind.mandelbrot {
    didSet {
      applyDefaults()
      changed()
    }
  }
  var centreReal = -0.5 {
    didSet { changed() }
  }
  var centreImaginary = 0.0 {
    didSet { changed() }
  }
  var span = 3.0 {
    didSet { changed() }
  }
  var maxIterations = 320.0 {
    didSet { changed() }
  }
  var juliaReal = -0.8 {
    didSet { changed() }
  }
  var juliaImaginary = 0.156 {
    didSet { changed() }
  }
  var power = 2.0 {
    didSet { changed() }
  }
  var novaRelaxation = 1.0 {
    didSet { changed() }
  }
  var coefficientA = 0.0 {
    didSet { changed() }
  }
  var coefficientB = 0.0 {
    didSet { changed() }
  }
  var coefficientC = 0.0 {
    didSet { changed() }
  }
  var coefficientD = 0.0 {
    didSet { changed() }
  }
  /// The camera of the three-dimensional kinds, in degrees for yaw and pitch.
  var cameraYaw = -35.0 {
    didSet { changed() }
  }
  var cameraPitch = 20.0 {
    didSet { changed() }
  }
  var cameraDistance = 3.5 {
    didSet { changed() }
  }
  /// The samples per side of each pixel, from 1 to 4.
  var supersampling = 1.0 {
    didSet { changed() }
  }
  /// Whether a ray-marched kind is drawn over a checkerboard floor. On for those kinds by default, as in the Android app.
  var showFloor = false {
    didSet { changed() }
  }

  /// Side of the square picture, in pixels.
  static let previewSize = 512

  private(set) var image: CGImage?
  private(set) var pngData: Data?
  private(set) var pngFileName = "fractal.png"
  private(set) var errorMessage: LocalizedStringKey?
  /// Bumped on every change. The view watches it and calls `refresh()` after a pause.
  private(set) var revision = 0

  /// The kit's ranges are applied when the picture is rendered, so values are not clamped here.
  var settings: EscapeTimeFractal.Settings {
    EscapeTimeFractal.Settings(
      kind: kind,
      centreReal: centreReal,
      centreImaginary: centreImaginary,
      span: span,
      maxIterations: Int(maxIterations.rounded()),
      juliaReal: juliaReal,
      juliaImaginary: juliaImaginary,
      power: Int(power.rounded()),
      novaRelaxation: novaRelaxation,
      coefficients: EscapeTimeFractal.Coefficients(
        a: coefficientA, b: coefficientB, c: coefficientC, d: coefficientD),
      camera: EscapeTimeFractal.Camera(
        yaw: cameraYaw, pitch: cameraPitch, distance: cameraDistance),
      supersampling: Int(supersampling.rounded()),
      showFloor: showFloor)
  }

  /// Renders the fractal on a background thread and encodes it as PNG.
  func refresh() async {
    let settings = settings
    let size = Self.previewSize
    let picture = await Task.detached(priority: .userInitiated) { () -> PNGPicture? in
      guard let raster = EscapeTimeFractal.render(settings, width: size, height: size),
        let cgImage = raster.toCGImage()
      else { return nil }
      // Same encoding as ExportEncoding.encode(_:as: .png, source: nil).
      return PNGPicture(cgImage, metadataSource: nil)
    }.value
    guard !Task.isCancelled else { return }

    guard let picture else {
      image = nil
      pngData = nil
      errorMessage = "The fractal could not be rendered."
      return
    }
    image = picture.image
    pngData = picture.png
    pngFileName = ExportNaming.fileName(stem: "fractal", fileExtension: "png", data: picture.png)
    errorMessage = nil
  }

  /// Sets the view, the Julia constant, the exponent, the iterations, the constants and the camera to
  /// the kind's defaults, and turns the floor off. The supersampling is kept, as the Android app keeps it.
  private func applyDefaults() {
    let view = kind.defaultView
    centreReal = view.centreReal
    centreImaginary = view.centreImaginary
    span = view.span
    maxIterations = Double(kind.defaultIterations)
    let julia = kind.defaultJuliaConstant
    juliaReal = julia.real
    juliaImaginary = julia.imaginary
    power = Double(kind.defaultPower)
    novaRelaxation = 1
    let coefficients = kind.defaultCoefficients
    coefficientA = coefficients.a
    coefficientB = coefficients.b
    coefficientC = coefficients.c
    coefficientD = coefficients.d
    let camera = kind.defaultCamera
    cameraYaw = camera.yaw
    cameraPitch = camera.pitch
    cameraDistance = camera.distance
    showFloor = kind.isRayMarched
  }

  private func changed() {
    revision += 1
  }
}
