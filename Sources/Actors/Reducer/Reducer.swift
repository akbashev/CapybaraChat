import Foundation

// TODO: Written straight away, right a proper wrapper type
public protocol Reducer<State, Action>: Actor {
  
  associatedtype State: Equatable
  associatedtype Action = Codable & Sendable
  
  func send(action: Action) async throws
  func getCurrentState() async throws -> State
  func getUpdates() async throws -> State
}

public enum ReducerError: Error {
  case notSubscribed
}
