import CoreGraphics
import Foundation
import ImageToolboxKit
import Observation
import PhotosUI
import SwiftUI

/// Holds the palette tool's state: the opened file, the format it is read as, the palette (its
/// name, colours and groups) and the format it is written as, and the Material You scheme built
/// from a picture. The palette keeps what the read format stores, so writing it again keeps it.
@MainActor
@Observable
final class PaletteToolModel {
  /// The format the open file is read as. Nil until the extension picks one or the user does.
  private(set) var readFormat: FileFormat?
  /// The format the palette is written as.
  var writeFormat = FileFormat.gimp {
    didSet { updateExport() }
  }

  private(set) var fileName: String?
  /// The palette that is shown and written: its name, its colours outside groups and its groups.
  private(set) var document = PaletteDocument()
  /// Every colour of the palette, the global colours first, as the palette section lists them.
  var colours: [PaletteColour] { document.allColours }
  private(set) var exportData: Data?
  private(set) var errorMessage: LocalizedStringKey?
  @ObservationIgnored private var fileData: Data?

  /// The picture the Material You scheme is built from. Choosing one finds its seed colour.
  var materialSelection: PhotosPickerItem? {
    didSet {
      guard let item = materialSelection else { return }
      materialLoadTask?.cancel()
      materialLoadTask = Task { await loadMaterialPicture(item) }
    }
  }
  /// Whether the Material You scheme is the dark one. Changing it rebuilds the scheme.
  var materialDark = false {
    didSet { rebuildMaterialScheme() }
  }
  /// The style of the Material You scheme. Changing it rebuilds the scheme.
  var materialStyle = MaterialSchemeStyle.tonalSpot {
    didSet { rebuildMaterialScheme() }
  }

  /// The picture the scheme comes from, decoded at full size for the preview.
  private(set) var materialPicture: LoadedImage?
  /// The scheme for the seed colour, the style and the dark setting. Nil until a picture is read.
  private(set) var materialScheme: MaterialColourScheme?
  private(set) var materialErrorMessage: LocalizedStringKey?
  @ObservationIgnored private var materialSeed: RGBA?
  @ObservationIgnored private var materialLoadTask: Task<Void, Never>?
  @ObservationIgnored private var materialBuildTask: Task<Void, Never>?

  /// Opens a palette file. Its extension picks the format. When several formats share the
  /// extension, the first one that reads the file is used. When the extension is unknown, the
  /// user chooses the format.
  func open(_ data: Data, fileName: String) {
    self.fileName = fileName
    fileData = data
    let candidates = FileFormat.readableFormats(forFileName: fileName)
    // When no candidate reads the file, the first one is kept so that its error is shown.
    readFormat = candidates.first { (try? $0.decode(data)) != nil } ?? candidates.first
    decode()
  }

  /// Reads the open file in the chosen format.
  func chooseReadFormat(_ format: FileFormat?) {
    readFormat = format
    decode()
  }

  /// The file could not be read at all, so there is no palette to show.
  func reportUnreadableFile() {
    fileName = nil
    fileData = nil
    readFormat = nil
    document = PaletteDocument()
    exportData = nil
    errorMessage = "The file could not be read."
  }

  /// Decodes the open file with the read format. Palette files are small, so this runs on the
  /// main actor.
  private func decode() {
    document = PaletteDocument()
    errorMessage = nil
    defer { updateExport() }

    guard let fileData else { return }
    guard let readFormat else {
      errorMessage = "Choose the format this file is saved in."
      return
    }
    do {
      let decoded = try readFormat.decode(fileData)
      guard !decoded.allColours.isEmpty else {
        errorMessage = "The palette has no colours."
        return
      }
      document = decoded
    } catch let failure as PaletteFormatError {
      errorMessage = Self.message(for: failure)
    } catch {
      errorMessage = "The file could not be read."
    }
  }

  /// The palette written in the write format, or nil when there is nothing to write.
  private func updateExport() {
    exportData = colours.isEmpty ? nil : writeFormat.encode(document)
  }

  /// Makes the Material You roles the palette's colours, so the Colours and Export sections save
  /// them in the chosen format. The open file is closed, because its colours are no longer shown.
  func useMaterialScheme() {
    guard let materialScheme else { return }
    fileName = nil
    fileData = nil
    readFormat = nil
    errorMessage = nil
    let colours = MaterialColourRole.paletteToolRows.flatMap { $0 }.map { role -> PaletteColour in
      let colour = materialScheme[role]
      return PaletteColour(
        name: role.displayName, red: colour.red, green: colour.green, blue: colour.blue)
    }
    document = PaletteDocument(colours: colours)
    updateExport()
  }

  private func loadMaterialPicture(_ item: PhotosPickerItem) async {
    materialErrorMessage = nil
    let loaded = await PhotoLoader.load(item)
    guard !Task.isCancelled else { return }
    guard let picked = loaded else {
      materialErrorMessage = "The picked file could not be read as an image."
      return
    }

    // The downscale and the seed colour are computed off the main actor. LoadedImage is Sendable,
    // so the CGImage can be handed to the detached task.
    let seed = await Task.detached(priority: .userInitiated) { () -> RGBA? in
      guard let raster = PaletteToolModel.downscaledRaster(picked.image, maxSide: 256) else {
        return nil
      }
      return MaterialSeedColour.extract(from: raster)
    }.value
    guard !Task.isCancelled else { return }
    guard let seed else {
      materialErrorMessage = "The pixels of this image could not be read."
      return
    }

    materialPicture = picked
    materialSeed = seed
    rebuildMaterialScheme()
  }

  /// Builds the scheme from the seed colour off the main actor. A newer change cancels the build
  /// that is still running, so only the latest settings reach the screen.
  private func rebuildMaterialScheme() {
    materialBuildTask?.cancel()
    guard let seed = materialSeed else { return }
    let dark = materialDark
    let options = MaterialColourScheme.Options(style: materialStyle)
    materialBuildTask = Task {
      let scheme = await Task.detached(priority: .userInitiated) {
        MaterialColourScheme.from(seedRGB: seed, dark: dark, options: options)
      }.value
      guard !Task.isCancelled else { return }
      materialScheme = scheme
    }
  }

  /// The picture as pixels whose longer side is at most `maxSide`. The seed colour is found from
  /// the pixels of a resized copy, so a smaller copy gives the same kind of result with less work.
  nonisolated static func downscaledRaster(_ image: CGImage, maxSide: Int) -> RasterImage? {
    let longest = max(image.width, image.height)
    guard longest > maxSide else { return RasterImage(image) }
    let scale = Double(maxSide) / Double(longest)
    let width = max(1, Int((Double(image.width) * scale).rounded()))
    let height = max(1, Int((Double(image.height) * scale).rounded()))
    guard let scaled = ImageGeometry.resize(image, width: width, height: height) else {
      return nil
    }
    return RasterImage(scaled)
  }

  private static func message(for failure: PaletteFormatError) -> LocalizedStringKey {
    switch failure {
    case .invalidHeader: "The file does not start with the header of this format."
    case .truncated: "The file ends before its data is complete."
    case .invalidFormat: "The file does not match this format."
    case .unknownBlockType: "The file has a block type this app does not know."
    case .unknownColourModel: "The file uses a colour model this app does not know."
    case .unknownColourType: "The file uses a colour type this app does not know."
    case .unknownColourSpace: "The file uses a colour space this app does not know."
    }
  }
}
