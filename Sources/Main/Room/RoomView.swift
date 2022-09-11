import ComposableArchitecture
import SwiftUI
import ActorSystems
import Models

struct RoomView: View {
  
  let store: Store<RoomState, RoomAction>
  @State var message: String = ""

  public var body: some View {
    WithViewStore(self.store) { viewStore in
      VStack(spacing: 0) {
        GuestsView(
          guests: viewStore.guests
            .sorted(by: { $0.status < $1.status })
        )
        Divider()
        MessagesView(
          messages: viewStore.messages,
          user: viewStore.user.name
        )
        if !viewStore.textingGuests.isEmpty {
          HStack {
            Spacer()
            TextingGuestsView(
              guests: viewStore.textingGuests
            )
          }.padding([.leading, .trailing], 16)
            .padding([.top], 8)
        }
        Divider()
          .padding([.top], 8)
        InputView(
          message: $message,
          send: { message in
            viewStore.send(.send(message: message))
          },
          change: { message in
            viewStore.send(.update(message.isEmpty ? .online : .texting))
          }
        )
        .padding()
      }.onAppear {
        viewStore.send(.connect)
      }
      .navigationBarTitle(viewStore.room.name.rawValue, displayMode: .inline)
    }
  }
}

struct MessagesView: View {
  
  let messages: [Room.Message]
  let user: User.Name
  
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
          Text(value.0.text)
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
                  value.0.user == user ? Color.blue : Color.green
                )
                .clipped()
            )
            .clipShape(Capsule())
            .frame(
              maxWidth: .infinity,
              alignment: value.0.user == user ? .trailing : .leading
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
  
  let guests: [Models.Room.Guest]
  
  var body: some View {
    Group {
      Text(
        guests
          .compactMap { $0.name.rawValue.first }
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
  
  let guests: [Models.Room.Guest]
  
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
            user: value.0
          )
        }
      }.padding(16)
    }
    .frame(height: 58)
  }
}

struct ProfileIconView: View {
  
  let user: Models.Room.Guest
  
  var body: some View {
    ZStack {
      Circle()
        .frame(width: 42, height: 42)
        .foregroundColor(
          color
        )
      Text(user.name.rawValue.capitalized.prefix(1))
      .font(.title3)
      .foregroundColor(.white)
    }
  }
  
  var color: Color {
    switch self.user.status {
      case .online:
        return .blue
      case .texting:
        return .green
      case .offline:
        return .gray
    }
  }
}
