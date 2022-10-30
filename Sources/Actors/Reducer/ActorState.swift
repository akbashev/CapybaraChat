enum ActorState<V> {
  case initial(String)
  case loaded(V)
  
  var value: V? {
    switch self {
      case .loaded(let value):
        return value
      case .initial:
        return nil
    }
  }
}

public enum ActorStateError: Error {
  case cantLoad
}
