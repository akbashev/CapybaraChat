import Foundation

public enum Models {
  public struct Room: Codable, Equatable {
    public let name: String
    public let guestIds: Set<String>
    public let messages: [String: [Message]]
    public let statuses: [String: Int]
  }
  
  public struct User: Codable, Equatable {
    public let name: String
    public let roomId: String?
  }
  
  public struct Message: Codable, Equatable {
    public let createdAt: Date
    public let text: String
  }
}
