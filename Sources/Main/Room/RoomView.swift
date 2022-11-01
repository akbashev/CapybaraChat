import SwiftUI
import ActorSystems
import Chat

struct RoomView: View {
  
  @StateObject private var room: ActorViewModel<Room.State, Room.Action, Room.Environment, Room.ID>
  @StateObject private var user: ActorViewModel<User.State, User.Action, User.Environment, User.ID>
  
  @State var message: String = ""
  
  init(
    id: String,
    user: ActorViewModel<User.State, User.Action, User.Environment, User.ID>
  ) {
    self._room = .init(wrappedValue: .init(clusterSystem: clusterSystem, id: id))
    self._user = .init(wrappedValue: user)
  }

  public var body: some View {
    VStack(spacing: 0) {
      GuestsView(
        guests: room.state?.statuses
          .map { .init(name: $0.key, status: $0.value) }
          .sorted(by: { $0.status < $1.status })
         ?? []
      )
      Divider()
      MessagesView(
        messages: room.state?.messages
          .map { value -> [MessagesView.Msg] in
            let (id, messages) = (value.key, value.value)
            return messages
              .map {
                MessagesView.Msg(
                  userId: id,
                  roomId: self.room.id,
                  message: $0
                )
              }
          }
          .flatMap { $0 }
          .sorted(by: { $0.message.createdAt > $1.message.createdAt }) ?? [],
        currentUser: user.id
      )
      if room.state?.textingGuests.isEmpty == false {
        HStack {
          Spacer()
          TextingGuestsView(
            guests: room.state?.textingGuests ?? []
          )
        }.padding([.leading, .trailing], 16)
          .padding([.top], 8)
      }
      Divider()
        .padding([.top], 8)
      InputView(
        message: $message,
        send: { message in
          room.send(.send(message: message, from: self.user.id))
        },
        change: { message in
          room.send(.update(status: message.isEmpty ? .online : .texting, from: self.user.id))
        }
      )
      .padding()
    }
    .navigationTitle(room.id)
    .onAppear {
      if let room = room.actor {
        self.room.send(.connect(user: user.id))
      }
    }
  }
}

struct MessagesView: View {
  
  struct Msg: Equatable {
    let userId: String
    let roomId: String
    let message: Message
  }
  
  let messages: [Msg]
  let currentUser: String
  
  var body: some View {
    ScrollView {
      LazyVStack {
        ForEach(
          Array(
            zip(
              messages,
              messages.indices
            )
          ),
          id: \.1
        ) { value in
          Text(value.0.message.text)
            .foregroundColor(.white)
            .padding([.leading, .trailing], 12)
            .padding([.top, .bottom], 8)
            .background(
              Capsule()
                .strokeBorder(
                  Color.clear,
                  lineWidth: 0
                )
                .background(
                  value.0.userId == currentUser ? Color.blue : Color.green
                )
                .clipped()
            )
            .clipShape(Capsule())
            .frame(
              maxWidth: .infinity,
              alignment: value.0.userId == currentUser ? .trailing : .leading
            )
            .rotationEffect(Angle(degrees: 180))
            .scaleEffect(x: -1.0, y: 1.0, anchor: .center)
            .transaction { transaction in
              transaction.animation = nil
            }
        }
      }
      .padding([.leading, .trailing], 16)
    }
    .rotationEffect(Angle(degrees: 180))
    .scaleEffect(x: -1.0, y: 1.0, anchor: .center)
  }
}

struct InputView: View {
  
  @Binding var message: String
  let send: (String) -> ()
  let change: (String) -> ()

  var body: some View {
    HStack {
      TextField(
        "Enter message",
        text: $message
      )
      Spacer()
      Button {
        send(message)
        message = ""
      } label: {
        Text("Send")
      }.disabled(message.isEmpty)
    }
    .onChange(of: message) { message in
      change(message)
    }
  }
}

struct TextingGuestsView: View {
  
  let guests: [User.ID]
  
  var body: some View {
    Group {
      Text(
        guests
          .compactMap { $0.first }
          .map { String($0) }
          .joined(separator: ",")
      )
      if !guests.isEmpty {
        Text("is writing...")
      }
    }
    .font(.subheadline)
    .foregroundColor(.gray)
  }
}


struct GuestsView: View {
  
  struct Guest: Equatable {
    let name: User.ID
    let status: User.Status
  }
  
  var guests: [Guest]
  
  var body: some View {
    ScrollView(.horizontal) {
      LazyHStack {
        ForEach(
          Array(
            zip(
              guests,
              guests.indices
            )
          ),
          id: \.1
        ) { value in
          ProfileIconView(
            user: value.0.name,
            status: value.0.status
          )
        }
      }.padding(16)
    }
    .frame(height: 58)
  }
}

struct ProfileIconView: View {
  
  let user: User.ID
  let status: User.Status

  var body: some View {
    ZStack {
      Circle()
        .frame(width: 42, height: 42)
        .foregroundColor(
          color
        )
      Text(user.capitalized.prefix(1))
      .font(.title3)
      .foregroundColor(.white)
    }
  }
  
  var color: Color {
    switch self.status {
      case .online:
        return .blue
      case .texting:
        return .green
      case .offline:
        return .gray
    }
  }
}

extension Room.State {
  var textingGuests: [User.ID] {
    self.statuses.filter { $0.value == .texting }
      .keys
      .compactMap { $0 }
  }
}
