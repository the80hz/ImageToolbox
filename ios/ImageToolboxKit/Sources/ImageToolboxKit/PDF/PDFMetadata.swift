import Foundation
import PDFKit

/// The title, author and other fields of a PDF's information dictionary. A blank field is not
/// set.
public struct PDFMetadata: Equatable, Sendable {
  public var title: String
  public var author: String
  public var subject: String
  /// Keywords separated by commas.
  public var keywords: String
  /// The program that made the original content.
  public var creator: String
  /// The program that wrote the file. PDFKit sets it when it writes, so it is read here and a
  /// value given for writing is ignored.
  public var producer: String

  public init(
    title: String = "", author: String = "", subject: String = "", keywords: String = "",
    creator: String = "", producer: String = ""
  ) {
    self.title = title
    self.author = author
    self.subject = subject
    self.keywords = keywords
    self.creator = creator
    self.producer = producer
  }

  /// The fields of the document.
  public static func read(from data: Data) throws -> PDFMetadata {
    let attributes = try PDFKitAccess.open(data).documentAttributes ?? [:]
    func text(_ attribute: PDFDocumentAttribute) -> String {
      switch attributes[attribute.rawValue] {
      case let value as String: value
      case let values as [String]: values.joined(separator: ", ")
      default: ""
      }
    }
    return PDFMetadata(
      title: text(.titleAttribute), author: text(.authorAttribute),
      subject: text(.subjectAttribute), keywords: text(.keywordsAttribute),
      creator: text(.creatorAttribute), producer: text(.producerAttribute))
  }

  /// The document with these fields. A blank field is removed from the file.
  public func write(to data: Data) throws -> Data {
    let document = try PDFKitAccess.open(data)
    var attributes: [AnyHashable: Any] = [:]
    func set(_ attribute: PDFDocumentAttribute, _ value: Any?) {
      attributes[attribute.rawValue] = value
    }
    let words = keywords.split(whereSeparator: { ",;".contains($0) })
      .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    set(.titleAttribute, title.isEmpty ? nil : title)
    set(.authorAttribute, author.isEmpty ? nil : author)
    set(.subjectAttribute, subject.isEmpty ? nil : subject)
    set(.keywordsAttribute, words.isEmpty ? nil : words)
    set(.creatorAttribute, creator.isEmpty ? nil : creator)
    document.documentAttributes = attributes
    return try PDFKitAccess.write(document)
  }

  /// The title, author, subject, keywords and creator of a document, for a copy of it.
  static func carriedAttributes(of document: PDFDocument) -> [AnyHashable: Any] {
    let source = document.documentAttributes ?? [:]
    let attributes: [PDFDocumentAttribute] = [
      .titleAttribute, .authorAttribute, .subjectAttribute, .keywordsAttribute, .creatorAttribute,
    ]
    var carried: [AnyHashable: Any] = [:]
    for attribute in attributes {
      carried[attribute.rawValue] = source[attribute.rawValue]
    }
    return carried
  }
}
