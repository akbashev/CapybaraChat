import ComposableArchitecture
import SwiftUI


struct UserView: View {
  
  var store: Store<UserState, UserAction>
  @State var roomName: String = ""
  
  init(
    store: Store<UserState, UserAction>
  ) {
    self.store = store
  }
  
  var body: some View {
    WithViewStore(self.store) { viewStore in
      VStack(spacing: 16) {
        Text("User: \(viewStore.user.name.rawValue)")
          .font(.headline)
          .frame(maxWidth: .infinity, alignment: .leading)
        TextField(
          "Enter room name",
          text: $roomName
        )
        NavigationLink(
          destination: IfLetStore(
            self.store.scope(
              state: \.roomState,
              action: UserAction.room
            )
          ) {
            RoomView(store: $0)
          } else: {
            ProgressView()
          },
          isActive: viewStore.binding(
            get: \.isRoomShowing,
            send: { UserAction.showRoom($0, self.roomName) }
          )
        ) {
          Text("Connect")
        }.disabled(roomName.isEmpty)
      }
      .padding()
      .onAppear {
        viewStore.send(.connect)
      }
      .onDisappear {
        viewStore.send(.disconnect)
      }
    }
  }
}

