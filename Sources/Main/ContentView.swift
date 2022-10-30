import Foundation
import SwiftUI
import Distributed
import Combine
import ActorSystems
import Actors

let clusterSystem: ClientServerActorSystem = try! ClientServerActorSystem
  .init(
    mode: .client(
      host: "localhost",
      port: 8888,
      protocol: .ws
    )
  )

public struct ContentView: View {
  
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
      UserView(id: self.userId)
    }
  }
}
