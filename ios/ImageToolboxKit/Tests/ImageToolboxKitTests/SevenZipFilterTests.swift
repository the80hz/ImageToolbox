import Foundation
import Testing

@testable import ImageToolboxKit

@Suite("7z BCJ and Delta filters")
struct SevenZipFilterTests {

  private typealias Entry = SevenZipArchive.Entry

  // The vectors were made with liblzma (Python's lzma module, FILTER_X86, FILTER_DELTA and
  // FILTER_LZMA2), not with the code under test. Each folder is wrapped in a 7z header by hand:
  // coder 0 is the filter, coder 1 is LZMA2, and the packed stream feeds coder 1.

  /// `sample.bin`: 256 bytes of calls and jumps with small and negative targets, after BCJ.
  private static let bcjVector = archiveVector(
    """
    N3q8ryccAAT4Eh6uBAEAAAAAAABFAAAAAAAAAL7i1wwBAP+ON6/p1mD+/1G06XimAABN++Vcj9Ug
    6Aa4AQB06Fce/v/pjfQAAOm9/AEAQOj8rgEAU7raFhDpCzL+/83I6S7QAQDpFkD+/3D41Fvpw0EA
    AFWqCKpzRN7G6NBD///px7UBAHq9Y+lB4f7/Zizpixv//2nF4um++f//OZ3k6a/kAQA5wpHp1Bn+
    /5XpYLkAAOHo5MUBAGAVx+nMeP7/6SSR///jtunH2QEAZG3oioH+/02rHdpXgMG9XOkE0gEA6La9
    AQDmY+hzu///kz7pGUEAADsm6carAQDosxsBAOmbs///LkjoyFEAALNdQ8nppIcAAOnpLkL+/x/v
    l67I6bQ4AAEEBgABCYEEAAcLAQACBAMDAQMhIQEQAAEMgQCBAAAICgGipdfnAAAFAREXAHMAYQBt
    AHAAbABlAC4AYgBpAG4AAAAAAA==
    """)

  /// The 256 bytes that the BCJ vector decodes to.
  private static let bcjOriginal = archiveVector(
    """
    jjev6c5g/v9RtOlppgAATfvlXI/VIOjrtwEAdOg2Hv7/6Wf0AADpkvwBAEDoy64BAFO62hYQ6dAx
    /v/NyOnszwEA6c8//v9w+NRb6XNBAABVqgiqc0TexuhzQ///6WW1AQB6vWPp1+D+/2Ys6Rob//9p
    xeLpRfn//zmd5Oku5AEAOcKR6UsZ/v+V6dG4AADh6E/FAQBgFcfpL3j+/+mCkP//47bpHtkBAGRt
    6NqA/v9Nqx3aV4DBvVzpRtEBAOjzvAEA5mPoqbr//5M+6UhAAAA7JunuqgEA6NYaAQDpubL//y5I
    6N9QAACzXUPJ6bKGAADp6TZB/v8f75euyOm0OA==
    """)

  /// `sample.bin`: 96 bytes after the Delta filter with distance 4.
  private static let deltaVector = archiveVector(
    """
    N3q8ryccAASzaC2BOwAAAAAAAABBAAAAAAAAADU4X2XgAF8AM10AAAoZH3B9Si1S+3sKBD16MFDW
    2AGzWS+MVOEi+2a0UhFdDkXGxtLhabwXlOcHYUqSxzAAAAEEBgABCTsABwsBAAIhAwEDISEBEAAB
    DGBgAAgKAXBJD6kAAAUBERcAcwBhAG0AcABsAGUALgBiAGkAbgAAAAAA
    """)

  /// The 96 bytes that the Delta vector decodes to.
  private static let deltaOriginal = archiveVector(
    """
    ACVKb5S53gMpTHOWveAHKlJ3mL3mCyxRe57B5A8yVXikwe4LMF16p83oFzJZhKPO9hM8WYKvyPUf
    OmWAq9bxHEhtgqfc8RZLYYS73vUoT2Kav9D1LkNkmbPWCSxHep2w
    """)

  /// Folders with only the PPMd coder, and with only the AES coder. Neither decodes a byte here:
  /// PPMd is refused, and AES needs a password first, so the packed bytes in them mean nothing.
  private static let ppmdFolder = archiveVector(
    """
    N3q8ryccAAS7No2IGAAAAAAAAAA8AAAAAAAAAAF8hDEAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcB
    BAYAAQkYAAcLAQABIwMEAQUGAAAQAAwoAAgKAfBxGsQAAAUBERMAcABwAG0AZAAuAGIAaQBuAAAA
    AAA=
    """)

  /// The folder with the AES coder.
  private static let aesFolder = archiveVector(
    """
    N3q8ryccAAQwrmCFGAAAAAAAAABEAAAAAAAAACT9LNYAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcB
    BAYAAQkYAAcLAQABJAbxBwEIEwEAAAAAAAAMKAAICgHwcRrEAAAFAREXAHMAZQBjAHIAZQB0AC4A
    YgBpAG4AAAAAAA==
    """)

  @Test("a BCJ folder written by liblzma is decoded")
  func decodesBCJFolder() throws {
    let entries = try SevenZipArchive.entries(in: Self.bcjVector)
    #expect(entries == [Entry(name: "sample.bin", data: Self.bcjOriginal)])
  }

  @Test("a Delta folder written by liblzma is decoded")
  func decodesDeltaFolder() throws {
    let entries = try SevenZipArchive.entries(in: Self.deltaVector)
    #expect(entries == [Entry(name: "sample.bin", data: Self.deltaOriginal)])
  }

  @Test("the x86 filter changes call and jump operands, and undoes its own encoding")
  func x86RoundTrip() {
    for seed in 1...8 {
      let original = Self.callHeavy(size: 3_000 + seed * 97, seed: UInt64(seed))
      var encoded = original
      SevenZipFilters.x86Convert(&encoded, encoding: true)
      #expect(encoded != original, "seed \(seed) left the data unchanged")
      SevenZipFilters.x86Convert(&encoded)
      #expect(encoded == original, "seed \(seed)")
    }
    for size in 0...5 {
      var short = [UInt8](repeating: 0xE8, count: size)
      SevenZipFilters.x86Convert(&short, encoding: true)
      SevenZipFilters.x86Convert(&short)
      #expect(short == [UInt8](repeating: 0xE8, count: size), "size \(size)")
    }
  }

  @Test("the Delta filter undoes its own encoding for every distance")
  func deltaRoundTrip() {
    let original = [UInt8](ArchiveTestData.mixed(1_500))
    for distance in 1...256 {
      var encoded = original
      Self.deltaEncode(&encoded, distance: distance)
      SevenZipFilters.deltaDecode(&encoded, distance: distance)
      #expect(encoded == original, "distance \(distance)")
    }
  }

  @Test("PPMd is refused, and an encrypted folder asks for its password")
  func refusedCoders() {
    #expect(throws: ArchiveCodecError.unsupported) {
      try SevenZipArchive.entries(in: Self.ppmdFolder)
    }
    #expect(throws: SevenZipArchive.PasswordFailure.passwordRequired) {
      try SevenZipArchive.entries(in: Self.aesFolder)
    }
  }

  /// Bytes rich in call (E8) and jump (E9) opcodes, with small or negative 32-bit operands.
  private static func callHeavy(size: Int, seed: UInt64) -> [UInt8] {
    var generator = ArchiveTestData.Generator(state: seed)
    var bytes: [UInt8] = []
    while bytes.count < size {
      let roll = generator.next() % 10
      guard roll < 3 else {
        bytes.append(UInt8(truncatingIfNeeded: generator.next()))
        continue
      }
      bytes.append(roll == 0 ? 0xE8 : 0xE9)
      var operand = UInt32(generator.next() % 0x40000)
      if generator.next() % 2 == 0 { operand |= 0xFFFC_0000 }
      bytes += LittleEndian.bytes(operand)
    }
    return Array(bytes.prefix(size))
  }

  /// The inverse of `SevenZipFilters.deltaDecode`, for the round trip.
  private static func deltaEncode(_ bytes: inout [UInt8], distance: Int) {
    for index in stride(from: bytes.count - 1, through: distance, by: -1) {
      bytes[index] &-= bytes[index - distance]
    }
  }
}
