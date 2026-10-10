import Foundation
import UIKit
import os

/// Opens the system print panel for a PDF. The panel prints the file as it is.
enum PDFPrinting {
  private static let logger = Logger(subsystem: "com.the80hz.imagetoolbox", category: "print")

  /// Whether this device can print at all.
  @MainActor
  static var isAvailable: Bool {
    UIPrintInteractionController.isPrintingAvailable
  }

  /// Shows the print panel for `data`. An iPad shows it as a popover that points at the bottom
  /// center of the key window, and an iPhone shows it as a sheet.
  @MainActor
  static func present(_ data: Data, jobName: String) {
    guard isAvailable else { return }
    let info = UIPrintInfo.printInfo()
    info.outputType = .general
    info.jobName = jobName
    let controller = UIPrintInteractionController.shared
    controller.printInfo = info
    controller.printingItem = data
    let finished: (UIPrintInteractionController, Bool, Error?) -> Void = { _, _, error in
      if let error {
        logger.error("Printing failed: \(error.localizedDescription, privacy: .public)")
      }
    }

    let shown: Bool
    if UIDevice.current.userInterfaceIdiom == .pad {
      guard let view = keyWindowRootView() else {
        logger.error("Printing failed: the app has no window to show the print panel in")
        return
      }
      let anchor = CGRect(x: view.bounds.midX, y: view.bounds.maxY, width: 1, height: 1)
      shown = controller.present(
        from: anchor, in: view, animated: true, completionHandler: finished)
    } else {
      shown = controller.present(animated: true, completionHandler: finished)
    }
    if !shown {
      logger.error("Printing failed: the print panel could not be shown")
    }
  }

  /// The root view of the key window, or nil when the app has no window on screen.
  @MainActor
  private static func keyWindowRootView() -> UIView? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
    return window?.rootViewController?.view
  }
}
