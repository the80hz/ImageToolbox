import ImageToolboxKit
import SwiftUI

struct FractalToolView: View {
  @State private var model = FractalToolModel()

  var body: some View {
    ToolScaffold(identifier: "fractals") {
      GlassSection("Preview") {
        if let image = model.image {
          PictureView(image: image)
        } else if let errorMessage = model.errorMessage {
          ErrorText(message: errorMessage)
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, minHeight: 200)
        }

        if let pngData = model.pngData {
          ShareFileButton(title: "Share PNG", data: pngData, fileName: model.pngFileName)
            .accessibilityIdentifier("fractals.share")

          SaveFileButton(title: "Save to Files", data: pngData, fileName: model.pngFileName)
            .accessibilityIdentifier("fractals.save")
        }
      }

      GlassSection("Fractal") {
        Picker("Kind", selection: Bindable(model).kind) {
          ForEach(EscapeTimeFractal.Kind.Family.allCases, id: \.self) { family in
            Section(Self.title(of: family)) {
              ForEach(EscapeTimeFractal.Kind.allCases.filter { $0.family == family }, id: \.self) {
                kind in
                Text(verbatim: Self.name(of: kind)).tag(kind)
              }
            }
          }
        }
        .accessibilityIdentifier("fractals.kind")

        ParameterSlider(
          title: "Max iterations",
          value: Bindable(model).maxIterations,
          range: 16...2000,
          step: 1,
          format: "%.0f"
        )
        ParameterSlider(
          title: "Supersampling",
          value: Bindable(model).supersampling,
          range: 1...4,
          step: 1,
          format: "%.0f"
        )
        // The ray-marched kinds are framed by the camera, so the centre and span do not apply.
        if !model.kind.isRayMarched {
          ParameterSlider(
            title: "Center real",
            value: Bindable(model).centreReal,
            range: -40...40,
            step: 0.001,
            format: "%.3f"
          )
          ParameterSlider(
            title: "Center imaginary",
            value: Bindable(model).centreImaginary,
            range: -40...40,
            step: 0.001,
            format: "%.3f"
          )
          ParameterSlider(
            title: "Span",
            value: Bindable(model).span,
            range: 0.001...1000,
            step: 0.001,
            format: "%.3f"
          )
        }
      }

      if model.kind.is3D {
        GlassSection("Camera") {
          ParameterSlider(
            title: "Camera yaw",
            value: Bindable(model).cameraYaw,
            range: -180...180,
            step: 0.5,
            format: "%.1f"
          )
          ParameterSlider(
            title: "Camera pitch",
            value: Bindable(model).cameraPitch,
            range: -89...89,
            step: 0.5,
            format: "%.1f"
          )
          ParameterSlider(
            title: "Camera distance",
            value: Bindable(model).cameraDistance,
            range: 0.5...20,
            step: 0.1,
            format: "%.2f"
          )
          // The floor belongs to the ray-marched kinds. The two three-dimensional attractors have none.
          if model.kind.isRayMarched {
            Toggle("Show floor", isOn: Bindable(model).showFloor)
              .accessibilityIdentifier("fractals.floor")
          }
        }
      }

      if model.kind.usesJuliaConstant {
        GlassSection("Julia constant") {
          ParameterSlider(
            title: "Real part",
            value: Bindable(model).juliaReal,
            range: -2...2,
            step: 0.001,
            format: "%.3f"
          )
          ParameterSlider(
            title: "Imaginary part",
            value: Bindable(model).juliaImaginary,
            range: -2...2,
            step: 0.001,
            format: "%.3f"
          )
        }
      }

      if model.kind.usesPower {
        GlassSection("Power") {
          ParameterSlider(
            title: "Power",
            value: Bindable(model).power,
            range: 2...16,
            step: 1,
            format: "%.0f"
          )
        }
      }

      if model.kind.usesNovaRelaxation {
        GlassSection("Nova") {
          ParameterSlider(
            title: "Relaxation",
            value: Bindable(model).novaRelaxation,
            range: -2...2,
            step: 0.001,
            format: "%.3f"
          )
        }
      }

      if model.kind.coefficientCount > 0 {
        let titles = Self.constantTitles(of: model.kind)
        let range = Self.constantRange(of: model.kind)
        GlassSection("Constants") {
          if model.kind.coefficientCount >= 1 {
            Self.constantSlider(titles[0], Bindable(model).coefficientA, range: range)
          }
          if model.kind.coefficientCount >= 2 {
            Self.constantSlider(titles[1], Bindable(model).coefficientB, range: range)
          }
          if model.kind.coefficientCount >= 3 {
            Self.constantSlider(titles[2], Bindable(model).coefficientC, range: range)
          }
          if model.kind.coefficientCount >= 4 {
            Self.constantSlider(titles[3], Bindable(model).coefficientD, range: range)
          }
        }
      }
    }
    .task(id: model.revision) {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      await model.refresh()
    }
  }

  private static func constantSlider(
    _ title: LocalizedStringKey, _ value: Binding<Double>, range: ClosedRange<Double>
  ) -> some View {
    ParameterSlider(title: title, value: value, range: range, step: 0.001, format: "%.3f")
  }

  /// The titles of the constants a to d of the kind. The folding kinds name them by their role, and
  /// the others keep the generic names.
  private static func constantTitles(of kind: EscapeTimeFractal.Kind) -> [LocalizedStringKey] {
    switch kind {
    case .quaternionJulia, .quaternionCubic:
      ["Quaternion X", "Quaternion Y", "Quaternion Z", "Quaternion W"]
    case .octahedralIFS, .icosahedralIFS: ["Scale", "Fold"]
    case .sierpinskiGasket, .apollonianGasket, .kleinian: ["Scale", "Fold", "Minimum radius"]
    case .lorenz: ["Sigma", "Rho", "Beta"]
    default: ["Constant a", "Constant b", "Constant c", "Constant d"]
    }
  }

  /// The range of the constants. The quaternion components are limited to ±2, as in the Android app.
  private static func constantRange(of kind: EscapeTimeFractal.Kind) -> ClosedRange<Double> {
    switch kind {
    case .quaternionJulia, .quaternionCubic: -2...2
    default: -100...100
    }
  }

  /// The headings of the groups in the picker.
  private static func title(of family: EscapeTimeFractal.Kind.Family) -> LocalizedStringKey {
    switch family {
    case .polynomial: "Polynomial maps"
    case .barnsley: "Barnsley maps"
    case .transcendental: "Transcendental maps"
    case .rational: "Rational and Newton maps"
    case .geometric: "Geometric sets"
    case .attractor: "Attractors"
    case .iterated: "Iterated systems and shapes"
    case .threeDimensional: "Three-dimensional fractals"
    }
  }

  /// The names of the sets. These are proper nouns, so they are not translated.
  private static func name(of kind: EscapeTimeFractal.Kind) -> String {
    switch kind {
    case .mandelbrot: "Mandelbrot"
    case .julia: "Julia"
    case .burningShip: "Burning ship"
    case .burningShipJulia: "Burning Ship Julia"
    case .perpendicularBurningShip: "Perpendicular burning ship"
    case .tricorn: "Tricorn"
    case .multibrot: "Multibrot"
    case .multicorn: "Multicorn"
    case .celtic: "Celtic"
    case .celticJulia: "Celtic Julia"
    case .phoenix: "Phoenix"
    case .spider: "Spider"
    case .manOWar: "Man-o’-War"
    case .lambda: "Lambda"
    case .buddhabrot: "Buddhabrot"
    case .buffalo: "Buffalo"
    case .alphaMandelbrot: "Alpha Mandelbrot"
    case .alphaMandelbrotJulia: "Alpha Mandelbrot Julia"
    case .zubieta: "Zubieta"
    case .cactus: "Cactus"
    case .barnsleyMandelbrot: "Barnsley Mandelbrot"
    case .barnsleyJulia: "Barnsley Julia"
    case .barnsleyII: "Barnsley II"
    case .barnsleyIII: "Barnsley III"
    case .sine: "Mandelbrot sine"
    case .cosine: "Mandelbrot cosine"
    case .juliaSine: "Julia sine"
    case .juliaCosine: "Julia cosine"
    case .sinh: "Mandelbrot sinh"
    case .juliaSinh: "Julia sinh"
    case .tetration: "Tetration"
    case .thorn: "Thorn"
    case .newton: "Newton"
    case .nova: "Nova"
    case .magnetI: "Magnet I"
    case .magnetII: "Magnet II"
    case .collatz: "Collatz"
    case .lyapunov: "Lyapunov"
    case .feather: "Feather"
    case .sierpinskiCarpet: "Sierpinski carpet"
    case .sierpinskiTriangle: "Sierpinski triangle"
    case .hopalong: "Hopalong"
    case .martin: "Martin"
    case .gingerbreadman: "Gingerbread man"
    case .clifford: "Clifford attractor"
    case .deJong: "De Jong attractor"
    case .ikeda: "Ikeda attractor"
    case .tinkerbell: "Tinkerbell map"
    case .gumowskiMira: "Gumowski–Mira"
    case .chip: "Chip"
    case .quadruptwo: "Quadruptwo"
    case .threeply: "Threeply"
    case .barnsleyFern: "Barnsley fern"
    case .vicsekCross: "Vicsek cross"
    case .heighwayDragon: "Heighway dragon"
    case .kochSnowflake: "Koch snowflake"
    case .pythagorasTree: "Pythagoras tree"
    case .hTree: "H-tree"
    case .hilbertCurve: "Hilbert curve"
    case .ifsDragon: "IFS dragon"
    case .ifsTwig: "IFS twig"
    case .christmasTree: "Christmas tree"
    case .mandelbulb: "Mandelbulb"
    case .mandelbox: "Mandelbox"
    case .mengerSponge: "Menger sponge"
    case .sierpinskiPyramid: "Sierpinski pyramid"
    case .quaternionJulia: "Julia set 3D"
    case .quaternionCubic: "Quaternion cubic"
    case .hybridMandelbulbJulia: "Hybrid Mandelbulb–Julia"
    case .sierpinskiGasket: "Sierpinski gasket"
    case .octahedralIFS: "Octahedral IFS"
    case .icosahedralIFS: "Icosahedral IFS"
    case .apollonianGasket: "Apollonian gasket"
    case .kleinian: "Kleinian"
    case .pickover: "Pickover"
    case .lorenz: "Lorenz"
    case .rossler: "Rössler"
    }
  }
}
