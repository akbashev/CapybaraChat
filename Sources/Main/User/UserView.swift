import SwiftUI
import Actors

struct UserView: View {
  
  @StateObject private var user: ActorViewModel<User>
  @State var roomName: String = ""
  
  init(
    id: String
  ) {
    self._user = .init(
      wrappedValue: .init(
        clusterSystem: clusterSystem,
        id: id
      )
    )
  }
  
  var body: some View {
    VStack(spacing: 16) {
      Text("User: \(user.state?.userId.rawValue ?? "")")
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
      TextField(
        "Enter room name",
        text: $roomName
      )
      NavigationLink(
        destination: RoomView(
          id: self.roomName,
          user: user
        )
      ) {
        Text("Connect")
      }.disabled(roomName.isEmpty)
    }
    .padding()
  }
}

