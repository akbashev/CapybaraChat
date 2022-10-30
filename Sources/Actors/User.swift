import Distributed
import Foundation
import ActorSystems
import Database
import AsyncPromise

public distributed actor User: Reducer {
  
  public typealias ActorSystem = ClientServerActorSystem
  
  private let userDatabase: UserDatabaseClient
  
  distributed public func getCurrentState() async throws -> State {
    try await self.initiateStateIfNeeded()
  }
  
  distributed public func getUpdates() async throws -> State {
    try await self.observer.subscribe()
  }
  
  private var observer: Observer<State> = .init()
  private var actorState: ActorState<State> {
    didSet {
      switch self.actorState {
        case let .loaded(value):
          Task {
            await self.observer.resolve(.success(value))
          }
        case .initial:
          break
      }
    }
  }
  
  distributed public func send(
    action: Action
  ) async throws {
    var state = try await getCurrentState()
    let task = self.reduce(&state, action)
    self.actorState = .loaded(state)
    if let action = try? await task.value {
      try await self.send(action: action)
    }
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
        let room = state.room
        let userId = state.userId
        return Task {
          try await room?.send(
            action: .update(
              status: status,
              from: userId
            )
          )
          return nil
        }
      case let .send(message):
        let room = state.room
        let userId = state.userId
        return Task {
          try await room?.send(
            action: .send(
              message: message,
              from: userId
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
    userDatabase: UserDatabaseClient,
    userId: String
  ) {
    self.actorSystem = actorSystem
    self.userDatabase = userDatabase
    self.actorState = .initial(userId)
  }
  
  private func initiateStateIfNeeded() async throws -> State {
    switch actorState {
      case .initial(let userId):
        let state: State = try await Task {
          do {
            let dbState = try await self.userDatabase.getUser(userId)
            return State(userId: .init(rawValue: dbState.name))
          } catch {
            switch error {
              case UserDatabaseClient.Error.notFound:
                try await self.userDatabase.updateUser(.init(name: userId))
                return State(userId: .init(rawValue: userId))
              default:
                throw ActorStateError.cantLoad
            }
          }
        }.value
        self.actorState = .loaded(state)
        return state
      case .loaded(let v):
        return v
    }
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
