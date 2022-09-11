import Foundation
import ComposableArchitecture
import Models
import Connection
import ActorSystems

struct RoomState: Equatable {
  var room: Room
  let user: User
  
  init(
    room: Room,
    user: User
  ) {
    self.room = room
    self.user = user
  }
}
  
extension RoomState {
  var messages: [Room.Message] {
    self.room.messages
  }
  
  var guests: [Room.Guest] {
    return self.room.guests
  }
  
  var textingGuests: [Room.Guest] {
    self.room.guests.filter { $0.status == .texting }
  }
}

enum RoomAction {
  case send(message: String)
  case update(Room.Guest.Status)
  case didFetch(Room)
  case connect
  case disconnect
}

struct RoomEnvironment {
  let client: RoomClient
}

struct RoomClient {
  typealias UserRoomPair = (user: User.Name, room: Room.Name)

  let send: (Room.Message, ClientServerConnectionClient.UserRoom) async throws -> ()
  let update: (Room.Guest.Status, ClientServerConnectionClient.UserRoom) async throws -> ()
  let connect: (ClientServerConnectionClient.UserRoom) async throws -> Room
  let disconnect: (ClientServerConnectionClient.UserRoom) async throws -> ()
  let getUpdates: (ClientServerConnectionClient.UserRoom) async throws -> AsyncStream<Room?>
}

let roomReducer = Reducer<RoomState, RoomAction, RoomEnvironment> { state, action, environment in
  let userRoom = ClientServerConnectionClient.UserRoom(
    user: state.user.name,
    room: state.room.name
  )
  switch action {
    case .connect:
      return .run { send in
        let connect = try await environment.client.connect(userRoom)
        await send(.didFetch(connect), animation: .default)
        // TODO: Add cancellation, otherwise could fired after state been removed.
        for await room in try await environment.client.getUpdates(userRoom) {
          if let room = room {
            await send(.didFetch(room), animation: .default)
          }
        }
      }
    case .didFetch(let room):
      state.room = room
      return .none
    case .disconnect:
      return .merge(
        .fireAndForget {
          try? await environment.client.disconnect(userRoom)
        }
      )
    case let .send(message):
      let message = Room.Message(
        user: state.user.name,
        createdAt: Date(),
        text: message
      )
      let user = state.user.name
      return .fireAndForget {
        try await environment.client.send(message, userRoom)
      }
    case let .update(status):
      return .fireAndForget {
        try await environment.client.update(status, userRoom)
      }
  }
}


extension RoomClient {
  static func live(
    client: ClientServerConnectionClient
  ) -> Self {
    .init(
      send: { message, userRoom in
        try await client
          .userRoomConnection(
            .init(
              user: userRoom.user,
              room: userRoom.room
            )
          )
          .add(message: message)
      },
      update: { status, userRoom in
        try await client
          .userRoomConnection(
            .init(
              user: userRoom.user,
              room: userRoom.room
            )
          )
          .set(status: status)
      },
      connect: { userRoom in
        try await client
          .userRoomConnection(
            .init(
              user: userRoom.user,
              room: userRoom.room
            )
          )
          .connect(
            to: userRoom.room
          )
      },
      disconnect: { userRoom in
        let connection = try await client
          .userRoomConnection(
            .init(
              user: userRoom.user,
              room: userRoom.room
            )
          )
        try await client
          .disconnect(
            connection,
            for: userRoom.user
          )
      },
      getUpdates: { userRoom in
        let connection = try await client
          .userRoomConnection(
            .init(
              user: userRoom.user,
              room: userRoom.room
            )
          )
        return AsyncStream { continuation in
          let task = Task {
            while !Task.isCancelled {
              let room = try await connection.getRoom()
              continuation.yield(room)
            }
            continuation.finish()
          }
          continuation.onTermination = { _ in task.cancel() }
        }
      }
    )
  }
}
