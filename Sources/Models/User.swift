import Foundation

public struct User: Equatable, Codable, Sendable, Hashable {
  
  // TODO: Add proper ID.
  public struct Name: RawRepresentable, Equatable, Codable, Sendable, Hashable {
    public let rawValue: String
    public init(
      rawValue: String
    ) {
      self.rawValue = rawValue
    }
  }
  
  public let name: Name
  public let roomIds: [String]

  public init(
    name: User.Name,
    roomIds: [String]
  ) {
    self.name = name
    self.roomIds = roomIds
  }
}
