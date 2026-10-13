import CoreGraphics
import CoreImage
import Foundation
import Vision

/// Removes the background of a picture with Vision's foreground instance mask, which finds the
/// salient subjects on the device. The result has transparency where the background was.
public enum BackgroundRemover {

  public enum Failure: Error, Equatable {
    /// Vision did not find a subject in the picture.
    case noSubject
    case rendering
  }

  public static func removeBackground(from image: CGImage) throws -> CGImage {
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do {
      try handler.perform([request])
    } catch {
      throw Failure.noSubject
    }
    guard let observation = request.results?.first else { throw Failure.noSubject }

    let mask: CVPixelBuffer
    do {
      mask = try observation.generateScaledMaskForImage(
        forInstances: observation.allInstances, from: handler)
    } catch {
      throw Failure.noSubject
    }

    let context = CIContext()
    let source = CIImage(cgImage: image)
    let maskImage = CIImage(cvPixelBuffer: mask)
    let transparent = CIImage(color: .clear).cropped(to: source.extent)
    let blend = CIFilter(
      name: "CIBlendWithMask",
      parameters: [
        kCIInputImageKey: source,
        kCIInputBackgroundImageKey: transparent,
        kCIInputMaskImageKey: maskImage,
      ])
    guard let output = blend?.outputImage,
      let result = context.createCGImage(output, from: source.extent)
    else { throw Failure.rendering }
    return result
  }
}
