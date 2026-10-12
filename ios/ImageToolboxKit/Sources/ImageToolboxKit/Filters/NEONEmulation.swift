import Foundation

/// Операции ARM NEON, на которые опирается Aire 0.18.1 и его Rust-зависимости на Android (arm64).
///
/// Результат этих операций определён спецификацией ARM, поэтому его можно воспроизвести точно.
/// Без них не сходятся байты эталона: оценка обратной величины даёт погрешность порядка 0.1 %,
/// и она хорошо видна после усечения или округления до целого.
enum NEONEmulation {
  /// `FRECPE` (`vrecpeq_f32`, Highway `ApproximateReciprocal`): оценка `1 / x` по 8 старшим битам
  /// мантиссы (Arm ARM, `FPRecipEstimate`), знак сохраняется. Для нуля результат бесконечность.
  static func reciprocalEstimate(_ value: Float) -> Float {
    if value == 0 { return .infinity }
    let bits = value.bitPattern
    let exponent = Int((bits >> 23) & 0xFF)
    let fraction = Int((bits >> 15) & 0xFF)
    let divisor = (256 + fraction) * 2 + 1
    let estimate = ((1 << 19) / divisor + 1) / 2
    let resultExponent = 253 - exponent
    guard resultExponent > 0, resultExponent < 255 else {
      return resultExponent <= 0 ? 0 : .infinity
    }
    let sign = bits & 0x8000_0000
    return Float(bitPattern: sign | UInt32(resultExponent << 23) | UInt32((estimate - 256) << 15))
  }

  /// `vfmodq_f32` из erydanos 0.2: `a - trunc(a * (1 / b)) * b`. `NaN` при переводе в целое даёт 0.
  static func fmod(_ dividend: Float, _ divisor: Float) -> Float {
    let quotient = dividend * (1 / divisor)
    let whole: Float = quotient.isNaN ? 0 : quotient.rounded(.towardZero)
    return dividend - whole * divisor
  }

  /// `vcvtaq_u32_f32`: округление до ближайшего с половинами от нуля, с насыщением в
  /// 0...UInt32.max.
  static func roundToUnsigned(_ value: Float) -> Int {
    guard value > 0 else { return 0 }
    return Int(min(value.rounded(), 4_294_967_040))
  }
}
