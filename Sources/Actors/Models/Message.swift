import Foundation

public struct Message: Equatable, Codable, Sendable, Hashable {
  
  public let createdAt: Date
  public let text: String
  
  public init(
    createdAt: Date,
    text: String
  ) {
    self.createdAt = createdAt
    self.text = text
  }
}
