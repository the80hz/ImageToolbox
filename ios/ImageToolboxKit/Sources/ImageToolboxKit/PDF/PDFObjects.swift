import CoreGraphics
import Foundation

/// Small readers for Core Graphics PDF objects, which the C API hands out through out parameters.
enum PDFObjects {

  static func dictionary(_ owner: CGPDFDictionaryRef, _ key: String) -> CGPDFDictionaryRef? {
    var value: CGPDFDictionaryRef?
    return CGPDFDictionaryGetDictionary(owner, key, &value) ? value : nil
  }

  static func stream(_ owner: CGPDFDictionaryRef, _ key: String) -> CGPDFStreamRef? {
    var value: CGPDFStreamRef?
    return CGPDFDictionaryGetStream(owner, key, &value) ? value : nil
  }

  static func array(_ owner: CGPDFDictionaryRef, _ key: String) -> CGPDFArrayRef? {
    var value: CGPDFArrayRef?
    return CGPDFDictionaryGetArray(owner, key, &value) ? value : nil
  }

  static func name(_ owner: CGPDFDictionaryRef, _ key: String) -> String? {
    var value: UnsafePointer<CChar>?
    return CGPDFDictionaryGetName(owner, key, &value) ? value.map { String(cString: $0) } : nil
  }

  static func integer(_ owner: CGPDFDictionaryRef, _ key: String) -> Int? {
    var value: CGPDFInteger = 0
    return CGPDFDictionaryGetInteger(owner, key, &value) ? Int(value) : nil
  }

  static func boolean(_ owner: CGPDFDictionaryRef, _ key: String) -> Bool? {
    var value: CGPDFBoolean = 0
    return CGPDFDictionaryGetBoolean(owner, key, &value) ? value != 0 : nil
  }

  /// The names under a key that holds a name or an array of names, such as `Filter`.
  static func names(_ owner: CGPDFDictionaryRef, _ key: String) -> [String] {
    if let single = name(owner, key) { return [single] }
    guard let list = array(owner, key) else { return [] }
    return (0..<CGPDFArrayGetCount(list)).compactMap { index in
      var value: UnsafePointer<CChar>?
      return CGPDFArrayGetName(list, index, &value) ? value.map { String(cString: $0) } : nil
    }
  }

  /// The numbers of an array, or an empty array when the key is not an array of numbers.
  static func numbers(_ owner: CGPDFDictionaryRef, _ key: String) -> [Double] {
    guard let list = array(owner, key) else { return [] }
    return (0..<CGPDFArrayGetCount(list)).compactMap { index in
      var value: CGPDFReal = 0
      return CGPDFArrayGetNumber(list, index, &value) ? Double(value) : nil
    }
  }

  /// The values of a dictionary that are streams, such as the `XObject` entries of resources.
  static func streams(in owner: CGPDFDictionaryRef) -> [CGPDFStreamRef] {
    final class Box { var streams: [CGPDFStreamRef] = [] }
    let box = Box()
    CGPDFDictionaryApplyBlock(
      owner,
      { _, object, _ in
        var value: CGPDFStreamRef?
        if CGPDFObjectGetValue(object, .stream, &value), let value { box.streams.append(value) }
        return true
      }, nil)
    return box.streams
  }
}
