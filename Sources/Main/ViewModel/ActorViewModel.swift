import Foundation
import ActorSystems
import Combine
import Distributed
import Messagable

@MainActor
class ActorViewModel<State, Action, Environment, ID>: ObservableObject
  where State: Codable & Sendable,
        Action: Codable & Sendable,
        ID: Codable {
  
  typealias Actor = Messagable<State, Action, Environment, ID>
  
  @Published public var state: State?
  let clusterSystem: ClientServerActorSystem
  let id: ID
  
  private lazy var stream: AsyncStream<State?> = .init { continuation in
    let task = Task {
      while !Task.isCancelled {
        let state = try await self.actor?.getUpdates()
        continuation.yield(state)
      }
      continuation.finish()
    }
    continuation.onTermination = { _ in
      task.cancel()
    }
  }
  
  private lazy var actorId: ClientServerActorSystem.ActorID = {
    self.clusterSystem
      .actorId(
        of: Actor.self,
        id: self.id
      )
  }()
  
  // TODO: Add reconnection, what if cluster system fail?
  lazy var actor: Actor? = {
    try? Actor.resolve(
      id: self.actorId,
      using: self.clusterSystem
    )
  }()
  
  init(
    clusterSystem: ClientServerActorSystem,
    id: ID
  ) {
    self.clusterSystem = clusterSystem
    self.id = id
    defer {
      Task {
        self.state = try await self.actor?.getCurrentState()
        for await state in self.stream {
          self.state = state
        }
      }
    }
  }
  
  func send(_ action: Action) {
    Task {
      try await self.actor?
        .send(action)
    }
  }
}
