import Distributed
import Foundation
import ActorSystems
import Database
import AsyncPromise

public distributed actor Room: Reducer {
  
  public typealias ActorSystem = ClientServerActorSystem

  distributed public func getCurrentState() async throws -> State {
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
  private let database: RoomDatabaseClient
  
  @discardableResult
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
      case let .connect(user):
        state.guests.insert(user)
        return Task {
          let userState = try await user.getCurrentState()
          return .update(status: .online, from: userState.userId)
        }
      case let .send(message, from):
        var messages = state.messages[from] ?? []
        messages.append(.init(createdAt: Date(), text: message))
        state.messages[from] = messages
        return Task { [state] in
          _ = await withTaskGroup(
            of: User.State?.self,
            returning: [User.State].self
          ) { group in
            for guest in state.guests {
              group.addTask {
                try? await guest.send(action: .roomDidUpdate(room: self))
              }
            }
            
            return await group
              .compactMap { $0 }
              .reduce(into: [], { $0.append($1) })
          }
          return nil
        }
      case let .update(status, from):
        state.statuses[from] = status
        return Task { [state] in
          _ = await withTaskGroup(
            of: User.State?.self,
            returning: [User.State].self
          ) { group in
            for guest in state.guests {
              group.addTask {
                try? await guest.send(action: .roomDidUpdate(room: self))
              }
            }
            
            return await group
              .compactMap { $0 }
              .reduce(into: [], { $0.append($1) })
          }
          return nil
        }
      case let .disconnect(user):
        state.statuses[user] = .offline
        return Task { return nil }
    }
  }
  
  public init(
    actorSystem: ActorSystem,
    database: RoomDatabaseClient,
    roomId: Name 
  ) {
    self.actorSystem = actorSystem
    self.database = database
    self._state = .init(roomId: roomId)
  }
}

extension Room {
  
  public struct State: Equatable, Codable {
    
    public struct Guest: Equatable, Codable {
      public let name: User.Name
      public let status: User.Status
    }
    
    public let roomId: Room.Name
    public var messages: [User.Name: [Message]] = [:]
    public var statuses: [User.Name: User.Status] = [:]

    public var guests: Set<User> = []
    
    public init(
      roomId: Room.Name
    ) {
      self.roomId = roomId
    }
  }
  
  public enum Action: Codable, Sendable {
    case connect(user: User)
    case send(message: String, from: User.Name)
    case update(status: User.Status, from: User.Name)
    case disconnect(user: User.Name)
  }
}
