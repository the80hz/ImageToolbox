import Foundation

/// `Trickle.fastBlur` (Trickle 1.9.3, `trickle/src/main/cpp/Utils.cpp`, `fastBlurImpl`):
/// 1. `Bitmap.createScaledBitmap(src, round(w * scale), round(h * scale), filter = true)`;
/// 2. 2. box-размытие радиусом `radius` по RGB (строки, затем столбцы; край повторяет крайний
///    пиксель; в каждом проходе деление на `2 radius + 1` целое с отбрасыванием остатка); альфа
///    результата всегда 255;
/// 3. 3. `createScaledBitmap` обратно в `Int(w / scale)` на `Int(h / scale)`. Android из-за этого
///    может вернуть картинку другого размера (на пиксель, для крошечных картинок сильнее); здесь
///    результат всегда исходного размера, чтобы цепочка фильтров не меняла размер. При `radius < 1`
///    Android возвращает исходную картинку без изменений.
///
/// Масштабирование `createScaledBitmap` с фильтром — билинейная выборка Skia с четырьмя битами
/// дробной части весов (`SkBitmapProcState`, `Filter_32_opaque`): центр пикселя результата
/// переводится в координаты источника, берутся ближайшие четыре пикселя, веса по 1/16 с усечением
/// дроби, сумма делится на 256 с усечением.
enum TrickleFastBlur {
  static func apply(_ image: RasterImage, scale: Float, radius: Int) -> RasterImage {
    guard radius >= 1 else { return image }
    let scaledWidth = max(1, Int((Float(image.width) * scale).rounded()))
    let scaledHeight = max(1, Int((Float(image.height) * scale).rounded()))
    let small = resample(
      image.pixels, width: image.width, height: image.height, toWidth: scaledWidth,
      toHeight: scaledHeight)
    let blurred = boxBlur(small, width: scaledWidth, height: scaledHeight, radius: radius)
    let pixels = resample(
      blurred, width: scaledWidth, height: scaledHeight, toWidth: image.width,
      toHeight: image.height)
    return RasterImage(width: image.width, height: image.height, pixels: pixels)
  }

  // MARK: Масштабирование

  /// Положение выборки по одной оси: два соседних пикселя и вес второго из 16.
  private struct Tap {
    let first: Int32
    let second: Int32
    let fraction: Int32
  }

  private static func taps(source: Int, destination: Int) -> [Tap] {
    let scale = Float(destination) / Float(source)
    let inverse = 1 / scale
    let last = source - 1
    return (0..<destination).map { index in
      // Центр пикселя результата в координатах источника, затем сдвиг на половину пикселя
      // (выборка идёт между центрами), 32.32 -> 16.16 с усечением вниз.
      let centre = inverse * (Float(index) + 0.5)
      let fractional = Int64(Double(centre) * 4_294_967_296.0) - 2_147_483_648
      let fixed = Int(fractional >> 16)
      let coarse = min(max(fixed >> 12, 0), last << 4)
      let second = min(max((fixed + 65536) >> 16, 0), last)
      return Tap(first: Int32(coarse >> 4), second: Int32(second), fraction: Int32(coarse & 15))
    }
  }

  static func resample(
    _ pixels: [UInt8], width: Int, height: Int, toWidth: Int, toHeight: Int
  ) -> [UInt8] {
    if width == toWidth && height == toHeight { return pixels }
    let columns = taps(source: width, destination: toWidth)
    let rows = taps(source: height, destination: toHeight)
    var output = [UInt8](repeating: 0, count: toWidth * toHeight * 4)
    pixels.withUnsafeBufferPointer { sourceBuffer in
      output.withUnsafeMutableBufferPointer { outputBuffer in
        guard let input = sourceBuffer.baseAddress, let target = outputBuffer.baseAddress else {
          return
        }
        let reader = SharedConstBuffer(base: input)
        let writer = SharedBuffer(base: target)
        ParallelBands.run(rows: toHeight, minimumRows: 16) { band in
          for y in band {
            let row = rows[y]
            let upper = reader.base + Int(row.first) * width * 4
            let lower = reader.base + Int(row.second) * width * 4
            let weightY = row.fraction
            for x in 0..<toWidth {
              let column = columns[x]
              let weightX = column.fraction
              let w00 = (16 - weightX) * (16 - weightY)
              let w01 = weightX * (16 - weightY)
              let w10 = (16 - weightX) * weightY
              let w11 = weightX * weightY
              let a = upper + Int(column.first) * 4
              let b = upper + Int(column.second) * 4
              let c = lower + Int(column.first) * 4
              let d = lower + Int(column.second) * 4
              let out = writer.base + (y * toWidth + x) * 4
              for channel in 0..<4 {
                let sum =
                  Int32(a[channel]) * w00 + Int32(b[channel]) * w01 + Int32(c[channel]) * w10
                  + Int32(d[channel]) * w11
                out[channel] = UInt8(truncatingIfNeeded: sum >> 8)
              }
            }
          }
        }
      }
    }
    return output
  }

  // MARK: Box-размытие

  /// Два прохода скользящей суммой с целым делением; альфа результата 255.
  private static func boxBlur(_ pixels: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
    let divisor = Int32(2 * radius + 1)
    var transient = [Int32](repeating: 0, count: width * height * 3)
    pixels.withUnsafeBufferPointer { source in
      for y in 0..<height {
        let line = y * width
        var sums = SIMD3<Int32>(repeating: 0)
        for offset in -radius...radius {
          sums &+= rgb(source, (line + min(max(offset, 0), width - 1)) * 4)
        }
        for x in 0..<width {
          let value = sums / divisor
          let index = (line + x) * 3
          transient[index] = value[0]
          transient[index + 1] = value[1]
          transient[index + 2] = value[2]
          let entering = rgb(source, (line + min(max(x + radius + 1, 0), width - 1)) * 4)
          let leaving = rgb(source, (line + min(max(x - radius, 0), width - 1)) * 4)
          sums = sums &+ entering &- leaving
        }
      }
    }
    var output = [UInt8](repeating: 255, count: width * height * 4)
    for x in 0..<width {
      var sums = SIMD3<Int32>(repeating: 0)
      for offset in -radius...radius {
        let row = min(max(offset, 0), height - 1)
        let index = (row * width + x) * 3
        sums &+= SIMD3(transient[index], transient[index + 1], transient[index + 2])
      }
      for y in 0..<height {
        let value = sums / divisor
        let out = (y * width + x) * 4
        output[out] = UInt8(truncatingIfNeeded: value[0])
        output[out + 1] = UInt8(truncatingIfNeeded: value[1])
        output[out + 2] = UInt8(truncatingIfNeeded: value[2])
        let enter = min(max(y + radius + 1, 0), height - 1)
        let leave = min(max(y - radius, 0), height - 1)
        let enterIndex = (enter * width + x) * 3
        let leaveIndex = (leave * width + x) * 3
        sums =
          sums
          &+ SIMD3(transient[enterIndex], transient[enterIndex + 1], transient[enterIndex + 2])
          &- SIMD3(transient[leaveIndex], transient[leaveIndex + 1], transient[leaveIndex + 2])
      }
    }
    return output
  }

  @inline(__always)
  private static func rgb(_ pixels: UnsafeBufferPointer<UInt8>, _ index: Int) -> SIMD3<Int32> {
    SIMD3(Int32(pixels[index]), Int32(pixels[index + 1]), Int32(pixels[index + 2]))
  }
}
