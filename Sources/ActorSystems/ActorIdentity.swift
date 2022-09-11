/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 Used as `ActorID` by all distributed actors in this sample app. It is used to uniquely identify any given actor within its actor system.
 */

import Foundation

public enum ConnectionProtocol: String, Sendable, Codable {
  case ws
}

public enum ActorIdentity: Hashable, Sendable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
  public struct Id: Hashable, Sendable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
    public let type: String
    public let _id: String
    
    public init(
      type: String,
      id: String
    ) {
      self.type = type
      self._id = id
    }
    
    var id: String {
      "\(type)-\(_id)"
    }
    
    public var description: String {
      self.id
    }
    
    public var debugDescription: String {
      self.id
    }
  }
  
  case simple(id: String)
  case full(id: Id, `protocol`: ConnectionProtocol, host: String, port: Int)
}

public extension ActorIdentity {
  
  static var random: Self {
    .simple(id: "\(UUID().uuidString)")
  }
  
  var id: String {
    switch self {
      case let .simple(id):
        return id
      case let .full(id, _, _, _):
        return id.id
    }
  }
  
  var description: String {
    switch self {
      case let .simple(id):
        return "\(id)"
      case let .full(id, proto, host, port):
        return "\(proto)://\(host):\(port)#\(id.id)"
    }
  }
  
  var debugDescription: String {
    switch self {
      case .simple:
        return "\(Self.self)(\(self.description))"
      case let .full(_, proto, host, port):
        return "Self.self(\(proto)://\(host):\(port)#\(self.description))"
    }
  }
  
}
