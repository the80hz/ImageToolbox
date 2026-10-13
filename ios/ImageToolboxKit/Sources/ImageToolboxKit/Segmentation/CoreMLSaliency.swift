import CoreGraphics
import CoreML
import CoreVideo
import Foundation

/// Finds the subject of a picture with a salient object model converted to Core ML, such as
/// U2-Net portable. The model takes one RGB image and returns one mask of the same size, with 1
/// where the subject is.
///
/// The input follows the Android app: the picture is resized to the model's size and the colours
/// are scaled to 0...1 (`pixel / 255`, no mean or deviation). The scaling is stored in the model
/// itself, as the image input's scale. This type only resizes the picture.
public struct CoreMLSaliency: Sendable {

  public enum Failure: Error, Equatable, Sendable {
    /// The model could not be compiled or loaded.
    case modelUnavailable
    /// The model is not one image in and one mask out.
    case unsupportedModel
    /// Core ML failed to run the model, or returned something that is not a mask.
    case prediction
    /// The picture could not be resized or the mask could not be scaled back.
    case rendering
  }

  /// Width of the picture the model reads, in pixels.
  public let inputWidth: Int
  /// Height of the picture the model reads, in pixels.
  public let inputHeight: Int

  private let model: ModelBox
  private let inputName: String
  private let outputName: String
  private let pixelFormat: OSType

  /// Loads a model.
  ///
  /// - Parameters:
  ///   - modelURL: A compiled model (`.mlmodelc`), or a `.mlpackage` or `.mlmodel` that is
  ///     compiled on the device. The compiled copy is kept in `cacheDirectory`, so the next load
  ///     does not compile again.
  ///   - computeUnits: Where Core ML may run the model.
  ///   - cacheDirectory: Where compiled copies are kept. The default is a folder in the user's
  ///     caches directory.
  public init(
    modelURL: URL,
    computeUnits: MLComputeUnits = .all,
    cacheDirectory: URL? = nil
  ) async throws {
    let compiled = try await Self.compiledModel(at: modelURL, cacheDirectory: cacheDirectory)
    let configuration = MLModelConfiguration()
    configuration.computeUnits = computeUnits
    let loaded: MLModel
    do {
      loaded = try await MLModel.load(contentsOf: compiled, configuration: configuration)
    } catch {
      throw Failure.modelUnavailable
    }

    let description = loaded.modelDescription
    guard description.inputDescriptionsByName.count == 1,
      let input = description.inputDescriptionsByName.first,
      let constraint = input.value.imageConstraint,
      description.outputDescriptionsByName.count == 1,
      let output = description.outputDescriptionsByName.first,
      output.value.type == .multiArray,
      constraint.pixelsWide > 0, constraint.pixelsHigh > 0,
      Self.bitmapInfo(for: constraint.pixelFormatType) != nil
    else { throw Failure.unsupportedModel }

    model = ModelBox(model: loaded)
    inputName = input.key
    outputName = output.key
    inputWidth = constraint.pixelsWide
    inputHeight = constraint.pixelsHigh
    pixelFormat = constraint.pixelFormatType
  }

  /// The subject's opacity at the size of `image`. The picture is resized to the model's input,
  /// the model runs, and its mask is scaled back to the size of `image`. Transparent pixels of
  /// the picture count as white.
  public func mask(for image: CGImage) throws -> SubjectMask {
    let buffer = try inputBuffer(from: image)
    let output: MLFeatureProvider
    do {
      let features = try MLDictionaryFeatureProvider(dictionary: [
        inputName: MLFeatureValue(pixelBuffer: buffer)
      ])
      output = try model.model.prediction(from: features)
    } catch {
      throw Failure.prediction
    }
    guard let array = output.featureValue(for: outputName)?.multiArrayValue else {
      throw Failure.prediction
    }
    let raw = try Self.maskValues(from: array)
    return try Self.scaledMask(raw, width: image.width, height: image.height)
  }

  // MARK: - Model

  /// `MLModel` is documented as safe to call from several threads for predictions.
  private struct ModelBox: @unchecked Sendable {
    let model: MLModel
  }

  /// The mask as the model wrote it: 0...1, row 0 at the top.
  private struct RawMask {
    let width: Int
    let height: Int
    let values: [Float]
  }

  /// Returns the URL of a compiled copy of the model, compiling it once per version.
  private static func compiledModel(at url: URL, cacheDirectory: URL?) async throws -> URL {
    switch url.pathExtension {
    case "mlmodelc":
      return url
    case "mlpackage", "mlmodel":
      break
    default:
      throw Failure.modelUnavailable
    }

    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: url.path) else { throw Failure.modelUnavailable }
    let caches =
      fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    let cache = cacheDirectory ?? caches.appendingPathComponent("CoreMLSaliency", isDirectory: true)
    let name = "\(url.deletingPathExtension().lastPathComponent)-\(fingerprint(of: url)).mlmodelc"
    let destination = cache.appendingPathComponent(name, isDirectory: true)
    if fileManager.fileExists(atPath: destination.path) { return destination }

    let temporary: URL
    do {
      temporary = try await MLModel.compileModel(at: url)
    } catch {
      throw Failure.modelUnavailable
    }
    do {
      try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
      try fileManager.moveItem(at: temporary, to: destination)
      return destination
    } catch {
      // Another load may have stored the same copy first. Otherwise the cache is not writable.
      if fileManager.fileExists(atPath: destination.path) {
        try? fileManager.removeItem(at: temporary)
        return destination
      }
      return temporary
    }
  }

  /// Total size and newest modification time of the files in a model, so a changed model gets a
  /// new cache entry.
  private static func fingerprint(of url: URL) -> String {
    let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
    var size = 0
    var newest = 0.0
    func add(_ file: URL) {
      guard let values = try? file.resourceValues(forKeys: Set(keys)),
        values.isRegularFile == true
      else { return }
      size += values.fileSize ?? 0
      newest = max(newest, values.contentModificationDate?.timeIntervalSince1970 ?? 0)
    }
    add(url)
    if let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) {
      for case let file as URL in files { add(file) }
    }
    return "\(size)-\(Int(newest))"
  }

  // MARK: - Input

  /// The bitmap layout of a pixel buffer Core ML may ask for, or nil for a format this type does
  /// not draw.
  private static func bitmapInfo(for format: OSType) -> UInt32? {
    switch format {
    case kCVPixelFormatType_32BGRA:
      CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    case kCVPixelFormatType_32ARGB:
      CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    case kCVPixelFormatType_32RGBA:
      CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    default:
      nil
    }
  }

  /// The picture resized to the model's input size, on a white background.
  private func inputBuffer(from image: CGImage) throws -> CVPixelBuffer {
    var created: CVPixelBuffer?
    let attributes =
      [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true,
      ] as CFDictionary
    CVPixelBufferCreate(
      kCFAllocatorDefault, inputWidth, inputHeight, pixelFormat, attributes, &created)
    guard let buffer = created, let info = Self.bitmapInfo(for: pixelFormat),
      let colourSpace = CGColorSpace(name: CGColorSpace.sRGB)
    else { throw Failure.rendering }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard
      let context = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer), width: inputWidth, height: inputHeight,
        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: colourSpace, bitmapInfo: info)
    else { throw Failure.rendering }
    let frame = CGRect(x: 0, y: 0, width: inputWidth, height: inputHeight)
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(frame)
    context.interpolationQuality = .high
    context.draw(image, in: frame)
    return buffer
  }

  // MARK: - Output

  /// Reads the last two dimensions of the array as the mask. Leading dimensions must be 1.
  /// Strides are respected, because Core ML may pad the rows.
  private static func maskValues(from array: MLMultiArray) throws -> RawMask {
    let shape = array.shape.map(\.intValue)
    let strides = array.strides.map(\.intValue)
    guard shape.count >= 2, strides.count == shape.count,
      shape.dropLast(2).allSatisfy({ $0 == 1 }),
      let width = shape.last, let height = shape.dropLast().last,
      width > 0, height > 0,
      let columnStride = strides.last, let rowStride = strides.dropLast().last
    else { throw Failure.prediction }

    var values = [Float](repeating: 0, count: width * height)
    if array.dataType == .float32 {
      array.withUnsafeBytes { bytes in
        let floats = bytes.bindMemory(to: Float.self)
        for y in 0..<height {
          for x in 0..<width {
            values[y * width + x] = floats[y * rowStride + x * columnStride]
          }
        }
      }
    } else {
      for y in 0..<height {
        for x in 0..<width {
          values[y * width + x] = array[y * rowStride + x * columnStride].floatValue
        }
      }
    }
    return RawMask(width: width, height: height, values: values)
  }

  /// Scales the model's mask to the size of the picture with a smooth filter and returns it as
  /// opacities. The mask is held in 8 bits while it is scaled, as the Android app does.
  private static func scaledMask(
    _ raw: RawMask, width: Int, height: Int
  ) throws -> SubjectMask {
    let bytes = raw.values.map { value in
      UInt8((value.isFinite ? min(max(value, 0), 1) : 0) * 255 + 0.5)
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
      let small = CGImage(
        width: raw.width, height: raw.height, bitsPerComponent: 8, bitsPerPixel: 8,
        bytesPerRow: raw.width, space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
        decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    else { throw Failure.rendering }

    var scaled = [UInt8](repeating: 0, count: width * height)
    let drawn = scaled.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
          bitmapInfo: CGImageAlphaInfo.none.rawValue)
      else { return false }
      context.interpolationQuality = .high
      context.draw(small, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { throw Failure.rendering }
    return SubjectMask(width: width, height: height, alpha: scaled.map { Double($0) / 255 })
  }
}
