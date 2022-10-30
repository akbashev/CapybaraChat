import Foundation

public enum Models {
  public struct Room: Codable, Equatable {
    public let name: String
    public let messages: [String: [Message]]
    public let statuses: [String: Int]
    
    public init(name: String, messages: [String : [Message]], statuses: [String : Int]) {
      self.name = name
      self.messages = messages
      self.statuses = statuses
    }
  }
  
  public struct User: Codable, Equatable {
    public let name: String
    
    public init(name: String) {
      self.name = name
    }
  }
  
  public struct Message: Codable, Equatable {
    public let createdAt: Date
    public let text: String
    
    public init(createdAt: Date, text: String) {
      self.createdAt = createdAt
      self.text = text
    }
  }
}
