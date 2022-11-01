import Foundation
import Database
import Messagable

public enum User {
  
  public typealias Actor = Messagable<User.State, User.Action, User.Environment, User.ID>

  public typealias ID = String
  
  public struct Environment {
    public let userDatabase: UserDatabaseClient
    
    public init(userDatabase: UserDatabaseClient) {
      self.userDatabase = userDatabase
    }
  }
  
  public struct State: Equatable, Codable, Sendable, Hashable {
    public let userId: Name
        
    public init(userId: Name) {
      self.userId = userId
    }
    // For future
    // private var lastMessage: LastMessage = Sending | Failed
    // private var messageQueue: [LastMessage] = []
  }
  
  public struct Action: Codable, Equatable {}
}

public let userReducer = ActorReducer<User.State, User.Action, User.Environment> { state, action, environment in
  Task { nil }
}

public let userStateLoader = ActorStateLoader<User.State, User.ID, User.Environment> { userId, environment in
  do {
    let dbState = try await environment
      .userDatabase
      .getUser(userId)
    return User.State(userId: dbState.name)
  } catch {
    switch error {
      case UserDatabaseClient.Error.notFound:
        try await environment
          .userDatabase
          .updateUser(.init(name: userId))
        return User.State(userId: userId)
      default:
        throw ReducerError.cantLoad
    }
  }
}
