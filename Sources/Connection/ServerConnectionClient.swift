import ActorSystems
import Models

// Can it be generalized?
// TODO: Rewrite using https://github.com/apple/swift-distributed-actors
/**
 Client to handle connection for server.
 */
public actor ServerConnectionClient {
    
  private let clusterSystem: ClientServerActorSystem
  
  private var roomConnections: [Room.Name: RoomConnection] = [:]
  
  public func roomConnection(
    _ room: Room.Name
  ) throws -> (RoomConnection) {
    if let connection = roomConnections[room] {
      return connection
    }
    let actorId = clusterSystem.actorId(
      of: Room.self,
      id: room.rawValue
    )
    let connection = try RoomConnection
      .resolve(
        id: actorId,
        using: clusterSystem
      )
    self.roomConnections[room] = connection
    return connection
  }
  
  public func disconnect(
    _ connection: RoomConnection
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

