import Foundation

// Models
extension User {
  // TODO: Add proper ID.
  public typealias Name = String
  
  public enum Status: Int, Equatable, Sendable, Codable, Comparable {
    case texting = 0
    case online = 1
    case offline = 2
    
    public static func < (lhs: User.Status, rhs: User.Status) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }
}

extension User.Status {
  init(_ status: Int) {
    switch status {
      case 0:
        self = .online
      case 1:
        self = .offline
      case 2:
        self = .texting
      default:
        self = .offline
    }
  }
}
