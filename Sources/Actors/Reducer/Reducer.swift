import Foundation

// TODO: Written straight away, right a proper wrapper type
public protocol Reducer<State, Action>: Actor {
  
  associatedtype State: Equatable
  associatedtype Action = Codable & Sendable
  
  @discardableResult
  func send(action: Action) async throws -> State
  func getCurrentState() async throws -> State
  func getUpdates() async throws -> State
}
