/**
 Still not sure how to observe await changes,
 so for now just made simple Promise type.
 Took idea here:
 https://gist.github.com/rjchatfield/d5ef79c7bc4bbdf4cb0e170ebd68e382
 and have updated a bit.
 */
public actor Promised<WrappedValue: Sendable> {
  
  private var _result: Result<WrappedValue, any Error>?
  
  private var observers: [CheckedContinuation<WrappedValue, any Error>] = []
  
  public var value: WrappedValue {
    get async throws {
      switch _result {
        case .success(let value):
          return value
        case .failure(let failure):
          throw failure
        case .none:
          return try await withCheckedThrowingContinuation(add(continuation:))
      }
    }
  }
  
  public nonisolated func resolve(with value: WrappedValue) {
    catching(.success(value))
  }
  
  public nonisolated func reject(with error: any Error) {
    catching(.failure(error))
  }
  
  public nonisolated func catching(_ result: Result<WrappedValue, any Error>) {
    Task { await _resolve(result: result) }
  }

  private func _resolve(result: Result<WrappedValue, any Error>) {
    switch _result {
      case .none:
        self._result = result
        for continuation in observers {
          continuation.resume(with: result)
        }
        self.observers.removeAll()
      case .some:
        break
    }
  }
  
  private func add(
    continuation: CheckedContinuation<WrappedValue, any Error>
  ) {
    observers.append(continuation)
  }
  
  public init() {}
}


public extension Promised {
  @discardableResult
  func wait() async -> WrappedValue? {
    return try? await self.value
  }
  
  @discardableResult
  func clearAndWait() async throws -> WrappedValue {
    self._result = nil
    return try await self.value
  }
}
