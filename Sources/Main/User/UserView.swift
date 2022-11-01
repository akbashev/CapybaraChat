import SwiftUI
import Chat

struct UserView: View {
  
  @StateObject private var user: ActorViewModel<User.State, User.Action, User.Environment, User.ID>
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
      Text("User: \(user.state?.userId ?? "")")
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

