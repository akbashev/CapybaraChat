import ActorSystems
import Models

// Can it be generalized?
/**
 Client to handle client-server connections.
 */
// TODO: Add listeners for dead connections (user shutdowns the app).
public actor ClientServerConnectionClient {
  
  public typealias UserRoom = UserRoomConnection.UserRoom
  
  private let clusterSystem: ClientServerActorSystem
  
  private var userConnections: [User.Name: UserConnection] = [:]
  private var userRoomConnections: [UserRoom: UserRoomConnection] = [:]
  
  public func userConnection(
    _ user: User.Name
  ) async throws -> (UserConnection) {
    if let connection = userConnections[user] {
      return connection
    }
    let actorId = clusterSystem.actorId(
      of: User.self,
      id: user.rawValue
    )
    let connection = try UserConnection
      .resolve(
        id: actorId,
        using: clusterSystem
      )
    self.userConnections[user] = connection
    return connection
  }
  
  public func userRoomConnection(
    _ userRoom: UserRoom
  ) async throws -> (UserRoomConnection) {
    if let connection = userRoomConnections[userRoom] {
      return connection
    }
    let actorId = clusterSystem.actorId(
      of: UserRoom.self,
      id: userRoom.id
    )
    let connection = try UserRoomConnection
      .resolve(
        id: actorId,
        using: clusterSystem
      )
    self.userRoomConnections[userRoom] = connection
    return connection
  }
  
  public func disconnect(
    _ connection: UserConnection
  ) async throws -> () {
    try await connection.disconnect()
    clusterSystem.resignID(connection.id)
  }
  
  public func disconnect(
    _ connection: UserRoomConnection,
    for user: User.Name
  ) async throws -> () {
    try await connection.disconnect()
    clusterSystem.resignID(connection.id)
  }
  
  public init(
    clusterSystem: ClientServerActorSystem
  ) {
    self.clusterSystem = clusterSystem
  }
}

