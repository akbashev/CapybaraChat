import Foundation

public struct Room: Equatable, Codable, Sendable, Hashable {
  
  // TODO: Add proper ID.
  public struct Name: RawRepresentable, Equatable, Codable, Sendable, Hashable {
    public let rawValue: String
    public init(
      rawValue: String
    ) {
      self.rawValue = rawValue
    }
  }
  
  public struct Guest: Equatable, Codable, Sendable, Hashable {
    
    public enum Status: Equatable, Codable, Sendable, Hashable, Comparable {
      case texting
      case online
      case offline
    }
    
    public let name: User.Name
    public var status: Status
    public var messages: [Message]

    public init(
      name: User.Name,
      status: Status,
      messages: [Message]
    ) {
      self.name = name
      self.status = status
      self.messages = messages
    }
  }
  
  public struct Message: Equatable, Codable, Sendable, Hashable {
    
    public let user: User.Name
    public let createdAt: Date
    public let text: String
    
    public init(
      user: User.Name,
      createdAt: Date,
      text: String
    ) {
      self.user = user
      self.createdAt = createdAt
      self.text = text
    }
  }

  
  public let name: Name
  public var guests: [Guest]
  public var messages: [Message] {
    self.guests
      .flatMap { $0.messages }
      .sorted(by: { $0.createdAt > $1.createdAt })
  }


  public init(
    name: Room.Name,
    guests: [Guest]
  ) {
    self.name = name
    self.guests = guests
  }
}
