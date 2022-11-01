import Foundation
import Distributed
import ActorSystems

// TODO: Written straight away
public final distributed actor Messagable<State, Action, Environment, ID>: Actor, Codable, Sendable
  where State: Codable & Sendable,
        Action: Codable & Sendable,
        ID: Codable {
  
  // Generalize
  public typealias ActorSystem = ClientServerActorSystem
  
  private var state: State
  private let reducer: ActorReducer<State, Action, Environment>
  private let stateLoader: ActorStateLoader<State, ID, Environment>
  private let environment: Environment
  
  distributed public func getCurrentState() async throws -> State {
    switch self.actorState {
      case .initial(let id):
        let state = try await stateLoader.load(id, environment)
        self.actorState = .loaded(state)
        return state
      case .loaded(let state):
        return state
    }
  }
  
  distributed public func getUpdates() async throws -> State {
    try await self.observer.subscribe()
  }
  
  private var observer: Observer<State> = .init()
  private var actorState: ActorState<State, ID> {
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
  
  distributed public func send(_ action: Action) async throws {
    var state = try await getCurrentState()
    let task = self.reducer.reduce(&state, action, environment)
    self.actorState = .loaded(state)
    if let action = try? await task.value {
      try await self.send(action)
    }
  }
  
  public init(
    actorSystem: ClientServerActorSystem,
    id: ID,
    state: State,
    environment: Environment,
    reducer: ActorReducer<State, Action, Environment>,
    stateLoader: ActorStateLoader<State, ID, Environment>
  ) {
    self.actorSystem = actorSystem
    self.state = state
    self.reducer = reducer
    self.environment = environment
    self.stateLoader = stateLoader
    self.actorState = .initial(id)
  }
}

public struct ActorReducer<State, Action, Environment> {
  public let reduce: (inout State, Action, Environment) -> Task<Action?, Error>
  
  public init(
    reduce: @escaping (inout State, Action, Environment) -> Task<Action?, Error>
  ) {
    self.reduce = reduce
  }
}

extension Messagable {
  private enum ActorState<V, ID>: Codable
  where V: Codable,
        ID: Codable {
    // When actor is created—it's not yet update it's state
    case initial(ID)
    // Loaded from db or other places
    case loaded(V)
    
    public var value: V? {
      switch self {
        case .loaded(let value):
          return value
        case .initial:
          return nil
      }
    }
  }
}

public struct ActorStateLoader<V, ID, Environment> {
  public let load: (ID, Environment) async throws -> V
  
  public init(
    load: @escaping (ID, Environment) async throws -> V
  ) {
    self.load = load
  }
}

public enum ReducerError: Error {
  case cantLoad
  case notSubscribed
}
