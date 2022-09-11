import Foundation
import SwiftUI
import Distributed
import Models
import Combine
import ComposableArchitecture
import ActorSystems
import Connection


public struct ContentView: View {
  
  // TODO: Add reconnection, what if cluster system fail?
  let client: ClientServerConnectionClient = .init(
    clusterSystem: try! ClientServerActorSystem
      .init(
        mode: .client(
          host: "localhost",
          port: 8888,
          protocol: .ws
        )
      )
  )
  
  var userId = {
    let userId = UserDefaults.standard.string(forKey: "userId")
    guard let userId = userId else {
      let generated = UUID().uuidString
      UserDefaults.standard.set(generated, forKey: "userId")
      return generated
    }
    return userId
  }()
  
  public init() {}
  
  public var body: some View {
    NavigationView {
      UserView(
        store: .init(
          initialState: .init(
            user: .init(
              name: .init(
                rawValue: userId
              ),
              roomIds: []
            )
          ),
          reducer: userReducer,
          environment: .init(
            roomClient: .live(client: client),
            userClient: .live(client: client)
          )
        )
      )
    }
  }
}
