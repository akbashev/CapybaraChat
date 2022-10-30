import Foundation

public extension Room {
  // TODO: Add proper ID.
  struct Name: RawRepresentable, Equatable, Codable, Sendable, Hashable {
    public let rawValue: String
    public init(
      rawValue: String
    ) {
      self.rawValue = rawValue
    }
  }
}
