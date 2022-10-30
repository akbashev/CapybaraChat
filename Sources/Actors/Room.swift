import Distributed
import Foundation
import ActorSystems
import Database

public distributed actor Room: Reducer {
  
  public typealias ActorSystem = ClientServerActorSystem

  private let roomDatabase: RoomDatabaseClient
  
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
      case let .connect(user):
        state.guests.insert(user)
        let roomId = state.roomId.rawValue
        return Task {
          let userState = try await user.getCurrentState()
          try await roomDatabase.addGuest((user: userState.userId.rawValue, room: roomId))
          return .update(status: .online, from: userState.userId)
        }
      case let .send(text, from):
        let message = Message(createdAt: Date(), text: text)
        var messages = state.messages[from] ?? []
        messages.append(message)
        state.messages[from] = messages
        let roomId = state.roomId
        let guests = state.guests
        return Task {
          try await roomDatabase.addMessage(.init(createdAt: message.createdAt, text: message.text), (user: from.rawValue, room: roomId.rawValue))
          _ = await withTaskGroup(
            of: Void?.self,
            returning: [Void].self
          ) { group in
            for guest in guests {
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
        let roomId = state.roomId
        let guests = state.guests
        return Task {
          try await roomDatabase.updateStatus(status.rawValue, (user: from.rawValue, room: roomId.rawValue))
          _ = await withTaskGroup(
            of: Void?.self,
            returning: [Void].self
          ) { group in
            for guest in guests {
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
        let roomId = state.roomId
        return Task {
          try await roomDatabase.updateStatus(User.Status.offline.rawValue, (user: user.rawValue, room: roomId.rawValue))
          return nil
        }
    }
  }
  
  public init(
    actorSystem: ActorSystem,
    roomDatabase: RoomDatabaseClient,
    roomId: String
  ) {
    self.actorSystem = actorSystem
    self.roomDatabase = roomDatabase
    self.actorState = .initial(roomId)
  }
  
  private func initiateStateIfNeeded() async throws -> State {
    switch actorState {
      case .initial(let roomId):
        let state: State = try await Task {
          do {
            let dbState = try await self.roomDatabase.getRoom(roomId)
            return State(
              roomId: .init(rawValue: roomId),
              messages: dbState.messages.reduce(
                into: [User.Name: [Message]](),
                {
                  $0[User.Name(rawValue: $1.key)] = $1.value
                    .map {
                      Message(
                        createdAt: $0.createdAt,
                        text: $0.text
                      )
                    }
                }
              ),
              statuses: dbState.statuses.reduce(
                into: [User.Name: User.Status](),
                {
                  $0[User.Name(rawValue: $1.key)] = User.Status($1.value)
                }
              )
            )
          } catch {
            switch error {
              case RoomDatabaseClient.Error.notFound:
                try await self.roomDatabase.updateRoom(.init(name: roomId, messages: [:], statuses: [:]))
                return State(roomId: .init(rawValue: roomId))
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

extension Room {
  
  public struct State: Equatable, Codable {
    
    public struct Guest: Equatable, Codable {
      public let name: User.Name
      public let status: User.Status
    }
    
    public let roomId: Room.Name
    public var messages: [User.Name: [Message]]
    public var statuses: [User.Name: User.Status]

    public var guests: Set<User> = []
    
    public init(
      roomId: Room.Name,
      messages: [User.Name: [Message]] = [:],
      statuses: [User.Name: User.Status] = [:]
    ) {
      self.roomId = roomId
      self.messages = messages
      self.statuses = statuses
    }
  }
  
  public enum Action: Codable, Sendable {
    case connect(user: User)
    case send(message: String, from: User.Name)
    case update(status: User.Status, from: User.Name)
    case disconnect(user: User.Name)
  }
}
