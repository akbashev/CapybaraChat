import Foundation

actor Observer<S: Sendable> {
  
  private var observers: [CheckedContinuation<S, any Error>] = []
  
  func subscribe() async throws -> S {
    try await withCheckedThrowingContinuation(add)
  }
  
  private func add(
    continuation: CheckedContinuation<S, any Error>
  ) {
    observers.append(continuation)
  }
  
  func resolve(
    _ result: Result<S, any Error>
  ) {
    self.observers.forEach { $0.resume(with: result) }
    self.observers.removeAll()
  }
}
