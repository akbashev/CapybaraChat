import Foundation
import Database
import Messagable

public enum Room {
  
  public typealias Actor = Messagable<Room.State, Room.Action, Room.Environment, Room.ID>
  
  public typealias ID = String
  
  public struct Environment {
    let roomDatabase: RoomDatabaseClient
    
    public init(
      roomDatabase: RoomDatabaseClient
    ) {
      self.roomDatabase = roomDatabase
    }
  }
  
  public struct State: Equatable, Codable, Sendable, Hashable {
    
    public struct Guest: Equatable, Codable, Sendable, Hashable {
      public let name: User.Name
      public let status: User.Status
    }
    
    public let roomId: Room.Name
    public var messages: [User.ID: [Message]]
    public var statuses: [User.ID: User.Status]

    public var guests: Set<User.ID> = []
    
    public init(
      roomId: Room.Name,
      messages: [User.ID: [Message]] = [:],
      statuses: [User.ID: User.Status] = [:]
    ) {
      self.roomId = roomId
      self.messages = messages
      self.statuses = statuses
    }
  }
  
  public enum Action: Codable, Sendable {
    case connect(user: User.ID)
    case send(message: String, from: User.ID)
    case update(status: User.Status, from: User.ID)
    case disconnect(user: User.ID)
  }
}

public let roomReducer = ActorReducer<Room.State, Room.Action, Room.Environment> { state, action, environment in
  switch action {
    case let .connect(user):
      state.guests.insert(user)
      let roomId = state.roomId
      return Task {
        try await environment.roomDatabase.addGuest((user: user, room: roomId))
        return .update(status: .online, from: user)
      }
    case let .send(text, from):
      let message = Message(createdAt: Date(), text: text)
      var messages = state.messages[from] ?? []
      messages.append(message)
      state.messages[from] = messages
      let roomId = state.roomId
      let guests = state.guests
      return Task {
        try await environment
          .roomDatabase
          .addMessage(
            .init(
              createdAt: message.createdAt,
              text: message.text
            ),
            (
              user: from,
              room: roomId
            )
          )
        return nil
      }
    case let .update(status, from):
      state.statuses[from] = status
      let roomId = state.roomId
      let guests = state.guests
      return Task {
        try await environment
          .roomDatabase
          .updateStatus(
            status.rawValue,
            (
              user: from,
              room: roomId
            )
          )
        return nil
      }
    case let .disconnect(user):
      state.statuses[user] = .offline
      let roomId = state.roomId
      return Task {
        try await environment
          .roomDatabase
          .updateStatus(
            User.Status.offline.rawValue,
            (
              user: user,
              room: roomId
            )
          )
        return nil
      }
  }
}

public let roomStateLoader = ActorStateLoader<Room.State, Room.ID, Room.Environment> { roomId, environment in
  do {
    let dbState = try await environment.roomDatabase.getRoom(roomId)
    return Room.State(
      roomId: roomId,
      messages: dbState.messages.reduce(
        into: [User.ID: [Message]](),
        {
          $0[$1.key] = $1.value
            .map {
              Message(
                createdAt: $0.createdAt,
                text: $0.text
              )
            }
        }
      ),
      statuses: dbState.statuses.reduce(
        into: [User.ID: User.Status](),
        {
          $0[$1.key] = User.Status($1.value)
        }
      )
    )
  } catch {
    switch error {
      case RoomDatabaseClient.Error.notFound:
        try await environment.roomDatabase.updateRoom(.init(name: roomId, messages: [:], statuses: [:]))
        return Room.State(roomId: roomId)
      default:
        throw ReducerError.cantLoad
    }
  }
}
