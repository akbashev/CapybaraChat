import Foundation
import ComposableArchitecture
import Models
import Connection
import ActorSystems

struct UserState: Equatable {
  var user: User
  var roomState: RoomState?
  var isRoomShowing: Bool = false
}

enum UserAction {
  case update(User)
  case room(RoomAction)
  case showRoom(Bool, String)
  case connect
  case disconnect
}

struct UserEnvironment {
  let roomClient: RoomClient
  let userClient: UserClient
}

struct UserClient {
  let connect: (User.Name) async throws -> (User)
  let disconnect: (User.Name) async throws -> ()
}

let userReducer = Reducer.combine(
  roomReducer
    .optional()
    .pullback(
      state: \.roomState,
      action: /UserAction.room,
      environment: { RoomEnvironment(client: $0.roomClient) }
    ),
  Reducer<UserState, UserAction, UserEnvironment> { state, action, environment in
    switch action {
      case .connect:
        let user = state.user.name
        return .run { send in
          let user = try await environment.userClient.connect(user)
          await send(.update(user))
        }
      case .disconnect:
        let user = state.user.name
        return .fireAndForget {
          try? await environment.userClient.disconnect(user)
        }
      case let .update(user):
        state.user = user
        return .none
      case .room(let state):
        return .none
      case let .showRoom(show, name):
        state.isRoomShowing = show
        if show {
          state.roomState = .init(
            room: Room(
              name: .init(rawValue: name),
              guests: []
            ),
            user: state.user
          )
          return .none
        } else {
          state.roomState = nil
          let user = state.user.name
          return .fireAndForget {
            try await environment.roomClient
              .disconnect(.init(user: user, room: .init(rawValue: name)))
          }
        }
    }
  }
)

extension UserClient {
  static func live(
    client: ClientServerConnectionClient
  ) -> Self {
    .init(
      connect: { user in
        try await client
          .userConnection(user)
          .connect(to: user)
      },
      disconnect: { user in
        let connection = try await client
          .userConnection(user)
        try await client.disconnect(connection)
      }
    )
  }
}
