import Foundation
import Actors
import ActorSystems
import Combine
import Distributed

@MainActor class ActorViewModel<T: DistributedActor & Reducer>: ObservableObject where T.ActorSystem == ClientServerActorSystem, T.ID == ActorIdentity {
  
  @Published public var state: T.State?
  let clusterSystem: ClientServerActorSystem
  let id: String
  
  private lazy var stream: AsyncStream<T.State?> = .init { continuation in
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
  
  private lazy var actorId: T.ID = {
    self.clusterSystem
      .actorId(of: T.self, id: self.id)
  }()
  
  // TODO: Add reconnection, what if cluster system fail?
  lazy var actor: T? = {
    try? T
      .resolve(
        id: self.actorId,
        using: self.clusterSystem
      )
  }()
  
  init(
    clusterSystem: ClientServerActorSystem,
    id: String
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
  
  func send(_ action: T.Action) {
    Task {
      try await self.actor?.send(action: action)
    }
  }
}
