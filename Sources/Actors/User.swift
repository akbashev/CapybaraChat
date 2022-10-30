import Distributed
import Foundation
import ActorSystems
import Database
import AsyncPromise

public distributed actor User: Reducer {
  
  public typealias ActorSystem = ClientServerActorSystem
  
  distributed public func getCurrentState() -> State {
    _state
  }
  
  distributed public func getUpdates() async throws -> State {
    try await promise.clearAndWait()
  }
  
  private lazy var promise: Promised<State> = .init()
  private var _state: State {
    didSet {
      self.promise.resolve(with: _state)
    }
  }
  private let database: UserDatabaseClient

  // TODO: Marked as `async throws`, check data racing, add queue or other solution
  distributed public func send(
    action: Action
  ) async throws -> State {
    var state = _state
    let task = self.reduce(&state, action)
    if let action = try await task.value {
      self._state = state
      return try await self.send(action: action)
    }
    self._state = state
    return state
  }
  
  private func reduce(
    _ state: inout State,
    _ action: Action
  ) -> Task<Action?, Error> {
    switch action {
      case let .join(room):
        state.room = room
        return Task {
          try await room.send(action: .connect(user: self))
          return nil
        }
      case .exit:
        state.room = nil
        return Task {
          .update(status: .offline)
        }
      case let .update(status):
        return Task { [state] in
          try await state.room?.send(
            action: .update(
              status: status,
              from: state.userId
            )
          )
          return nil
        }
      case let .send(message):
        return Task { [state] in
          try await state.room?.send(
            action: .send(
              message: message,
              from: state.userId
            )
          )
          return nil
        }
      case let .roomDidUpdate(room):
        state.room = room
        return Task { return nil }
    }
  }
  
  public init(
    actorSystem: ActorSystem,
    database: UserDatabaseClient,
    userId: Name
  ) {
    self.actorSystem = actorSystem
    self.database = database
    self._state = .init(userId: userId)
  }
}

// Messagable
extension User {
  public struct State: Equatable, Codable {
    public let userId: Name
    
    public var room: Room?
    // For future
    // private var lastMessage: LastMessage = Sending | Failed
    // private var messageQueue: [LastMessage] = []
  }
  
  public enum Action: Codable, Sendable {
    case join(room: Room)
    case exit
    case send(message: String)
    case update(status: User.Status)
    case roomDidUpdate(room: Room)
  }
}
