import CoreGraphics
import CoreML
import Foundation
import Testing

@testable import ImageToolboxKit

/// The converted models live in the app's resources. Tests read them from the repository, and
/// are skipped where the files are missing.
private enum SaliencyModels {
  static let directory: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // ImageToolboxKitTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // ImageToolboxKit
    .deletingLastPathComponent()  // ios
    .appendingPathComponent("ImageToolbox/Resources/Models", isDirectory: true)

  static var u2netp: URL { directory.appendingPathComponent("u2netp.mlpackage") }

  static func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }
}

/// A scratch folder for compiled models, removed when the test ends.
private func withCache<T>(_ body: (URL) async throws -> T) async throws -> T {
  let cache = FileManager.default.temporaryDirectory
    .appendingPathComponent("saliency-tests-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: cache) }
  return try await body(cache)
}

@Suite("Core ML saliency")
struct CoreMLSaliencyTests {

  /// A bright shaded ball in the middle of a dark picture.
  private static func picture(width: Int = 400, height: Int = 300) throws -> CGImage {
    let context = try #require(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red: 0.12, green: 0.14, blue: 0.2, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let colours =
      [
        CGColor(red: 1, green: 0.95, blue: 0.8, alpha: 1),
        CGColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1),
      ] as CFArray
    let gradient = try #require(
      CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1]))
    let centre = CGPoint(x: Double(width) / 2, y: Double(height) / 2)
    let radius = Double(min(width, height)) * 0.32
    context.saveGState()
    context.addEllipse(
      in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    context.clip()
    context.drawRadialGradient(
      gradient, startCenter: CGPoint(x: centre.x - radius / 3, y: centre.y + radius / 3),
      startRadius: 0, endCenter: centre, endRadius: radius * 1.1, options: [])
    context.restoreGState()
    return try #require(context.makeImage())
  }

  @Test(
    "U2-Net portable returns a mask of the picture's size with the bright subject in front",
    .enabled(if: SaliencyModels.exists(SaliencyModels.u2netp)))
  func u2netpFindsSubject() async throws {
    try await withCache { cache in
      let saliency = try await CoreMLSaliency(
        modelURL: SaliencyModels.u2netp, computeUnits: .cpuOnly, cacheDirectory: cache)
      #expect(saliency.inputWidth == 320 && saliency.inputHeight == 320)

      let image = try Self.picture()
      let mask = try saliency.mask(for: image)
      #expect(mask.width == 400 && mask.height == 300)
      #expect(mask.alpha.count == 400 * 300)
      #expect(mask.alpha.allSatisfy { $0 >= 0 && $0 <= 1 })

      // Row 0 is the top. The ball is in the middle. The corners are dark background.
      #expect(mask.alpha[150 * 400 + 200] > 0.8)
      for corner in [(4, 4), (395, 4), (4, 295), (395, 295)] {
        #expect(mask.alpha[corner.1 * 400 + corner.0] < 0.2)
      }
    }
  }

  @Test(
    "the mask follows the size of any picture",
    .enabled(if: SaliencyModels.exists(SaliencyModels.u2netp)))
  func maskFollowsPictureSize() async throws {
    try await withCache { cache in
      let saliency = try await CoreMLSaliency(
        modelURL: SaliencyModels.u2netp, computeUnits: .cpuOnly, cacheDirectory: cache)
      // Smaller than the model's input, and very wide.
      let small = try saliency.mask(for: try Self.picture(width: 96, height: 64))
      #expect(small.width == 96 && small.height == 64)
      let wide = try saliency.mask(for: try Self.picture(width: 640, height: 80))
      #expect(wide.width == 640 && wide.height == 80)
    }
  }

  @Test(
    "the mask can be applied to the picture as a cut-out",
    .enabled(if: SaliencyModels.exists(SaliencyModels.u2netp)))
  func maskCutsOut() async throws {
    try await withCache { cache in
      let saliency = try await CoreMLSaliency(
        modelURL: SaliencyModels.u2netp, computeUnits: .cpuOnly, cacheDirectory: cache)
      let image = try Self.picture()
      let mask = try saliency.mask(for: image)
      let raster = try #require(RasterImage(image))
      let cutout = mask.applied(to: raster)
      #expect(cutout.pixel(x: 200, y: 150).alpha > 200)
      #expect(cutout.pixel(x: 4, y: 4).alpha < 50)
    }
  }

  @Test(
    "a model compiled once is reused from the cache",
    .enabled(if: SaliencyModels.exists(SaliencyModels.u2netp)))
  func compiledCopyIsReused() async throws {
    try await withCache { cache in
      _ = try await CoreMLSaliency(
        modelURL: SaliencyModels.u2netp, computeUnits: .cpuOnly, cacheDirectory: cache)
      _ = try await CoreMLSaliency(
        modelURL: SaliencyModels.u2netp, computeUnits: .cpuOnly, cacheDirectory: cache)
      let entries = try FileManager.default.contentsOfDirectory(atPath: cache.path)
      #expect(entries.count == 1)
      #expect(entries.first?.hasSuffix(".mlmodelc") == true)
    }
  }

  @Test("a missing or unknown model file is reported")
  func missingModel() async throws {
    try await withCache { cache in
      let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent("no-such-model-\(UUID().uuidString).mlpackage")
      await #expect(throws: CoreMLSaliency.Failure.modelUnavailable) {
        try await CoreMLSaliency(modelURL: missing, cacheDirectory: cache)
      }
      // The extension is checked before the file is read, so the file need not exist.
      let unknown = URL(fileURLWithPath: "model.onnx")
      await #expect(throws: CoreMLSaliency.Failure.modelUnavailable) {
        try await CoreMLSaliency(modelURL: unknown, cacheDirectory: cache)
      }
    }
  }
}
