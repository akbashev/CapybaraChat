import Distributed
import Foundation
import ActorSystems
import Models
import Database

/**
 User connection is one to one.
 */
public distributed actor UserConnection {
  
  public typealias User = Models.User
  
  public enum Error: Swift.Error {
    case noUser
  }
  
  public typealias ActorSystem = ClientServerActorSystem

  private var _user: User?
  private let database: UserDatabaseClient
  
  @discardableResult
  distributed public func connect(
    to name: User.Name
  ) async throws -> User {
    if let user = self._user,
       user.name == name {
      return user
    }
    
    let user = try await getFromDb(for: name)
    self._user = user
    return user
  }
  
  private func getFromDb(
    for name: User.Name
  ) async throws -> User {
    if let user = try? await database.getUser(name) {
      return user
    }
    
    let user = User(
      name: name,
      roomIds: []
    )
    try await database.updateUser(user)
    return user
  }
  
  distributed internal func disconnect() async throws {
    self._user = nil
  }
  
  public init(
    actorSystem: ActorSystem,
    database: UserDatabaseClient
  ) {
    self.actorSystem = actorSystem
    self.database = database
  }
}
