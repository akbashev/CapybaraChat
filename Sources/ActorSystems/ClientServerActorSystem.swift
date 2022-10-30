import Foundation
import Distributed
import NIO
import NIOWebSocket
import NIOPosix
#if os(iOS) || os(macOS)
import NIOTransportServices
#endif
import NIOCore
import NIOHTTP1
import NIOWebSocket
import NIOFoundationCompat
import NIOConcurrencyHelpers

/**
 This is Apple's code with some refactor:
 https://developer.apple.com/documentation/swift/tictacfish_implementing_a_game_using_distributed_actors
 
 For now idea is to make system for client-server connection. And for server:
 https://github.com/apple/swift-distributed-actors
 */

@available(iOS 16.0, *)
public final class ClientServerActorSystem: DistributedActorSystem,
                                            @unchecked Sendable {
  
  public typealias ActorID = ActorIdentity
  public typealias CallID = UUID
  public typealias InvocationEncoder = NIOInvocationEncoder
  public typealias InvocationDecoder = NIOInvocationDecoder
  public typealias SerializationRequirement = any Codable
  
  // ==== Channels
  let group: EventLoopGroup
  // TODO: Could it be moved to let? 🤔
  private var channel: ClientServerActorSystem.SystemChannel?
  
  // === Configuration
  public let mode: ClientServerActorSystem.SystemMode
  
  fileprivate var managedActors: [ActorID: any DistributedActor] = [:]
  // === Handle replies
  fileprivate var inFlightCalls: [CallID: CheckedContinuation<Data, Error>] = [:]
  
  // === On-Demand resolve handler
  typealias OnDemandResolveHandler = (ActorID) -> (any DistributedActor)?
  
  fileprivate var resolveOnDemandHandler: OnDemandResolveHandler? = nil
  
  private let lock = NSLock()
  private let replyLock = NSLock()

  public init(
    mode: ClientServerActorSystem.SystemMode
  ) throws {
    self.mode = mode
    
    /**
     Note: this sample system implementation assumes that clients are iOS devices,
     and as such will be always using NetworkFramework (via NIOTransportServices),
     for the client-side. This does not have to always be the case, but generalizing/making
     it configurable is left as an exercise for interested developers.
     */
    let group = { () -> EventLoopGroup in
      switch mode {
        case .client:
          return NIOTSEventLoopGroup()
        case .server:
          return MultiThreadedEventLoopGroup(
            numberOfThreads: 1
          )
      }
    }()
    self.group = group
    // Start networking
    self.channel = try {
      switch mode {
        case .client(let host, let port, _):
          return .client(
            try ClientServerActorSystem
              .client(
                host: host,
                port: port,
                group: group,
                system: self
              )
          )
        case .server(let host, let port, _):
          return .server(
            try ClientServerActorSystem
              .server(
                host: host,
                port: port,
                group: group,
                system: self
              )
          )
      }
    }()
    
    log("websocket", "\(Self.self) initialized in mode: \(mode)")
  }
  
  @TaskLocal private static var alreadyLocked: Bool = false
  public func resolve<Act>(
    id: ActorIdentity,
    as actorType: Act.Type
  ) throws -> Act?
  where Act : DistributedActor, ActorIdentity == Act.ID
  {
    if !Self.alreadyLocked {
      lock.lock()
    }
    defer {
      if !Self.alreadyLocked {
        lock.unlock()
      }
    }
     
    guard let found = managedActors[id] else {
      log("resolve[\(self.mode)]", "Not found locally, ID: \(id)")
      if let resolveOnDemand = self.resolveOnDemandHandler {
        log("resolve\(self.mode)", "Resolve on demand, ID: \(id)")
        
        let resolvedOnDemandActor = Self.$alreadyLocked.withValue(true) {
          resolveOnDemand(id)
        }
        if let resolvedOnDemandActor = resolvedOnDemandActor {
          log("resolve", "Attempt to resolve on-demand. ID: \(id) as \(resolvedOnDemandActor)")
          if let wellTyped = resolvedOnDemandActor as? Act {
            log("resolve", "Resolved on-demand, as: \(Act.self)")
            return wellTyped
          } else {
            log("resolve", "Resolved on demand, but wrong type: \(type(of: resolvedOnDemandActor))")
            throw SystemError.resolveFailed(id: id)
          }
        } else {
          log("resolve", "Resolve on demand: \(id)")
        }
      }
      
      log("resolve", "Resolved as remote. ID: \(id)")
      return nil // definitely remote, we don't know about this ActorID
    }
    
    guard let wellTyped = found as? Act else {
      throw SystemError.resolveFailedToMatchActorType(found: type(of: found), expected: Act.self)
    }
    
    print("RESOLVED LOCAL: \(wellTyped)")
    return wellTyped
  }
  
  @TaskLocal static var actorIDHint: ActorID? = nil
  public func assignID<Act>(
    _ actorType: Act.Type
  ) -> ActorIdentity
  where Act : DistributedActor, ActorIdentity == Act.ID
  {
    // Implements `id` hinting via a task-local.
    // IDs must never be reused, so if this were to happen this causes a crash here.
    if let hintedID = Self.actorIDHint {
      if !Self.alreadyLocked {
        lock.lock()
      }
      defer {
        if !Self.alreadyLocked {
          lock.unlock()
        }
      }
      
      if let existingActor = self.managedActors[hintedID] {
        preconditionFailure(
          """
          Illegal re-use of ActorID (\(hintedID))!
          Already used by: \(existingActor), yet attempted to assign to \(actorType)!
          """
        )
      }
      
      return hintedID
    }
    
    let uuid = UUID().uuidString
    let typeFullName = "\(Act.self)"
    guard typeFullName.split(separator: ".").last != nil else {
      return .simple(id: uuid)
    }
    
    return .simple(id: "\(uuid)")
  }
  
  public func actorReady<Act>(
    _ actor: Act
  )
  where Act : DistributedActor, ActorIdentity == Act.ID {
    log("actorReady[\(self.mode)]", "resign ID: \(actor.id)")
    
    if !Self.alreadyLocked {
      lock.lock()
    }
    defer {
      if !Self.alreadyLocked {
        self.lock.unlock()
      }
    }
    
    self.managedActors[actor.id] = actor
  }
  
  public func resignID(
    _ id: ActorIdentity
  ) {
    log("resignID[\(self.mode)]", "resign ID: \(id)")
    lock.lock()
    defer {
      lock.unlock()
    }
    
    self.managedActors.removeValue(forKey: id)
  }
  
  public func makeInvocationEncoder() -> NIOInvocationEncoder {
    .init()
  }
}

extension ClientServerActorSystem {
  func resolveAny(
    id: ActorID,
    resolveReceptionist: Bool = false
  ) -> (any DistributedActor)? {
    lock.lock()
    defer { lock.unlock() }
    
    switch id {
      case let .full(_, proto, host, port)
        where (proto == self.mode.`protocol` && host == self.mode.host && port == self.mode.port):
        guard let resolved = managedActors[id] else {
          log("resolve", "here")
          if let resolveOnDemand = self.resolveOnDemandHandler {
            log("resolve", "got handler")
            return Self.$alreadyLocked.withValue(true) {
              if let resolvedOnDemandActor = resolveOnDemand(id) {
                log("resolve", "Resolved ON DEMAND: \(id) as \(resolvedOnDemandActor)")
                return resolvedOnDemandActor
              } else {
                log("resolve", "not resolved")
                return nil
              }
            }
          } else {
            log("resolve", "here")
          }
          
          log("resolve", "RESOLVED REMOTE: \(id)")
          return nil // definitely remote, we don't know about this ActorID
        }
        
        log("resolve", "here: \(resolved)")
        return resolved
      default:
        return nil
    }
  }
}

extension ClientServerActorSystem {
  @available(iOS 16.0, *)
  public struct ResultHandler: DistributedTargetInvocationResultHandler {
    
    public typealias SerializationRequirement = any Codable
    
    let actorSystem: ClientServerActorSystem
    let callID: ClientServerActorSystem.CallID
    let system: ClientServerActorSystem
    let channel: NIOCore.Channel
    
    public func onReturn<Success: Codable>(
      value: Success
    ) async throws {
      log("handler-onReturn", "Write to channel: \(channel)")
      let encoder = JSONEncoder()
      encoder.userInfo[.actorSystemKey] = actorSystem
      let returnValue = try encoder.encode(value)
      let envelope = ReplyEnvelope(
        callID: self.callID,
        sender: nil,
        value: returnValue
      )
      channel.write(
        WireEnvelope.reply(envelope),
        promise: nil
      )
    }
    
    public func onReturnVoid() async throws {
      log("handler-onReturnVoid", "Write to channel: \(channel)")
      let envelope = ReplyEnvelope(
        callID: self.callID,
        sender: nil,
        value: "".data(using: .utf8)!
      )
      channel.write(
        WireEnvelope.reply(envelope),
        promise: nil
      )
    }
    
    public func onThrow<Err: Error>(
      error: Err
    ) async throws {
      log("handler", "onThrow: \(error)")
      // Naive best-effort carrying the error name back to the caller;
      // Always be careful when exposing error information -- especially do not ship back the entire description
      // or error of a thrown value as it may contain information which should never leave the node.
      let envelope = ReplyEnvelope(
        callID: self.callID,
        sender: nil,
        value: "".data(using: .utf8)!
      )
      channel.write(
        WireEnvelope.reply(envelope),
        promise: nil
      )
    }
  }
}

extension ClientServerActorSystem {
  public struct ReplyEnvelope: Sendable, Codable {
    let callID: ClientServerActorSystem.CallID
    let sender: ClientServerActorSystem.ActorID?
    let value: Data
  }
}

extension ClientServerActorSystem {
  public struct CallEnvelope: Sendable, Codable {
    let callID: ClientServerActorSystem.CallID
    let recipient: ActorIdentity
    let invocationTarget: String
    let genericSubs: [String]
    let args: [Data]
  }
}

extension ClientServerActorSystem {
  public enum WireEnvelope: Sendable, Codable {
    case call(CallEnvelope)
    case reply(ReplyEnvelope)
    case connectionClose
  }
}

extension ClientServerActorSystem {
  
  public enum SystemMode {
    case client(host: String, port: Int, protocol: ConnectionProtocol)
    case server(host: String, port: Int, protocol: ConnectionProtocol)
    
    var isClient: Bool {
      switch self {
        case .client:
          return true
        default:
          return false
      }
    }
    
    var isServer: Bool {
      switch self {
        case .server:
          return true
        default:
          return false
      }
    }
    
    var host: String {
      switch self {
        case .client(let host, _, _):
          return host
        case .server(let host, _, _):
          return host
      }
    }
    
    var port: Int {
      switch self {
        case .client(_, let port, _):
          return port
        case .server(_, let port, _):
          return port
      }
    }
    
    var `protocol`: ConnectionProtocol {
      switch self {
        case .client(_, _, let proto):
          return proto
        case .server(_, _, let proto):
          return proto
      }
    }
  }
  
}

extension ClientServerActorSystem {
  public enum SystemChannel {
    case server(NIOCore.Channel)
    case client(NIOCore.Channel)
    
    public var nio: NIOCore.Channel {
      switch self {
        case .client(let channel):
          return channel
        case .server(let channel):
          return channel
      }
    }
  }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// - MARK: RemoteCall implementations

@available(iOS 16.0, *)
extension ClientServerActorSystem {
  public func remoteCall<Act, Err, Res>(
    on actor: Act,
    target: RemoteCallTarget,
    invocation: inout InvocationEncoder,
    throwing: Err.Type,
    returning: Res.Type
  ) async throws -> Res
  where Act: DistributedActor, Act.ID == ActorID, Err: Error, Res: Codable
  {
    log("remote-call", "Act type \(Act.Type.self)")
    log("remote-call", "Call to: \(actor.id), target: \(target), target.identifier: \(target.identifier)")
    
    let channel = try self.selectChannel(for: actor.id)
    log("remote-call", "channel: \(channel)")
    
    log("remote-call", "Prepare [\(target)] call...")
    let replyData = try await withCallIDContinuation(recipient: actor) { callID in
      let callEnvelope = CallEnvelope(
        callID: callID,
        recipient: actor.id,
        invocationTarget: target.identifier,
        genericSubs: invocation.genericSubs,
        args: invocation.argumentData
      )
      let wireEnvelope = WireEnvelope.call(callEnvelope)
      
      log("remote-call", "Write envelope: \(wireEnvelope)")
      channel.writeAndFlush(wireEnvelope, promise: nil)
    }
    
    do {
      let decoder = JSONDecoder()
      decoder.userInfo[.actorSystemKey] = self
      
      return try decoder.decode(Res.self, from: replyData)
    } catch {
      throw SystemError.decodingError(error: error)
    }
  }
  
  public func remoteCallVoid<Act, Err>(
    on actor: Act,
    target: RemoteCallTarget,
    invocation: inout InvocationEncoder,
    throwing: Err.Type
  ) async throws
  where Act: DistributedActor, Act.ID == ActorID, Err: Error
  {
    log("remote-call-void", "Call to: \(actor.id), target: \(target), target.identifier: \(target.identifier)")
    
    let channel = try selectChannel(for: actor.id)
    log("remote-call-void", "channel: \(channel)")
    
    log("remote-call-void", "Prepare [\(target)] call...")
    _ = try await withCallIDContinuation(recipient: actor) { callID in
      let callEnvelope = CallEnvelope(
        callID: callID,
        recipient: actor.id,
        invocationTarget: target.identifier,
        genericSubs: invocation.genericSubs,
        args: invocation.argumentData
      )
      let wireEnvelope = WireEnvelope.call(callEnvelope)
      
      log("remote-call-void", "Write envelope: \(wireEnvelope)")
      channel.writeAndFlush(wireEnvelope, promise: nil)
    }
    
    log("remote-call-void", "COMPLETED CALL: \(target)")
  }
  
  func selectChannel(
    for actorID: ActorID
  ) throws -> NIOCore.Channel {
    switch actorID {
      case let .full(_, proto, host, port)
        where (proto == self.mode.`protocol` && host == mode.host && port == mode.port):
        // We implemented a pretty naive actor system; that only handles ONE connection to a backend.
        // In general, a websocket transport could open new connections as it notices identities to hosts.
        switch mode {
          case .server:
            throw
            """
              Server selecting specific connections to send messages to is not implemented;
              This would allow the server to *initiate* request/reply exchanges, rather than only perform replies.
            """
          case .client:
            self.lock.lock()
            defer { self.lock.unlock() }
            
            switch self.channel {
              case .client:
                log("select-channel", "Client channel \(self.channel!.nio)")
                log("select-channel", "Channel pipelines \(self.channel!.nio.pipeline)")
                return self.channel!.nio
              default:
                throw "Wrong channel"
            }
        }
      default:
        throw "No protocol, host or port in WS actor system assigned actor identity! Was: \(actorID)"
    }
  }
  
  private func withCallIDContinuation<Act>(
    recipient: Act,
    body: (CallID) -> Void
  ) async throws -> Data
  where Act: DistributedActor
  {
    let data = try await withCheckedThrowingContinuation { continuation in
      let callID = UUID()
      
      self.replyLock.lock()
      self.inFlightCalls[callID] = continuation
      self.replyLock.unlock()
      
      log("remote-call-withCC", "Stored callID: [\(callID)], waiting for reply...")
      body(callID)
    }
    
    log("remote-call-withCC", "Resumed call, data: \(String(data: data, encoding: .utf8)!)")
    return data
  }
}


// ==== ----------------------------------------------------------------------------------------------------------------
// - MARK: Client-side networking stack

@available(iOS 16.0, *)
extension ClientServerActorSystem {
  static func client(
    host: String,
    port: Int,
    group: EventLoopGroup,
    system: ClientServerActorSystem
  ) throws -> NIOCore.Channel {
    try NIOTSConnectionBootstrap(group: group)
    // Enable SO_REUSEADDR.
      .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
      .channelInitializer { channel in
        
        let httpHandler = InitialRequestHandler(target: .init(host: host, port: port))
        
        let websocketUpgrader = NIOWebSocketClientUpgrader(
          // TODO: Should it stay here? 🤔 Even SwiftNIO example has it...
          requestKey: "OfS0wDaT5NoxF2gqm7Zj2YtetzM=",
          upgradePipelineHandler: { (channel: NIOCore.Channel, _: HTTPResponseHead) in
            channel.pipeline.addHandlers(
              MessageOutboundHandler(actorSystem: system),
              ActorMessageInboundHandler(actorSystem: system)
              // WebSocketActorReplyHandler(actorSystem: self)
            )
          })
        
        let config: NIOHTTPClientUpgradeConfiguration = (
          upgraders: [websocketUpgrader],
          completionHandler: { _ in
            channel.pipeline.removeHandler(httpHandler, promise: nil)
          }
        )
        
        return channel.pipeline
          .addHTTPClientHandlers(withClientUpgrade: config)
          .flatMap {
            channel.pipeline.addHandler(httpHandler)
          }
      }
      .connect(host: host, port: port)
      .wait()
  }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// - MARK: Server-side networking stack

@available(iOS 16.0, *)
extension ClientServerActorSystem {
  static func server(
    host: String,
    port: Int,
    group: EventLoopGroup,
    system: ClientServerActorSystem
  ) throws -> NIOCore.Channel {
    // Upgrader performs upgrade from HTTP to WS connection
    let upgrader = NIOWebSocketServerUpgrader(
      shouldUpgrade: { (channel: NIOCore.Channel, head: HTTPRequestHead) in
        // Always upgrade; this is where we could do some auth checks
        channel.eventLoop.makeSucceededFuture(HTTPHeaders())
      },
      upgradePipelineHandler: { (channel: NIOCore.Channel, _: HTTPRequestHead) in
        channel.pipeline.addHandlers(
          MessageOutboundHandler(actorSystem: system),
          ActorMessageInboundHandler(actorSystem: system)
        )
      }
    )
    
    let bootstrap = ServerBootstrap(group: group)
    // Specify backlog and enable SO_REUSEADDR for the server itself
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
    
    // Set the handlers that are applied to the accepted Channels
      .childChannelInitializer { channel in
        let httpHandler = HTTPHandler()
        let config: NIOHTTPServerUpgradeConfiguration = (
          upgraders: [upgrader],
          completionHandler: { _ in
            channel.pipeline.removeHandler(httpHandler, promise: nil)
          }
        )
        return channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: config).flatMap {
          channel.pipeline.addHandler(httpHandler)
        }
      }
    
    // Enable SO_REUSEADDR for the accepted Channels
      .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
    
    let channel = try bootstrap.bind(host: host, port: port).wait()
    
    guard channel.localAddress != nil else {
      fatalError("Address was unable to bind. Please check that the socket was not closed or that the address family was understood.")
    }
    
    return channel
  }
}

extension ClientServerActorSystem {
  
  // MARK: Client-side handlers
  struct ConnectTo {
    let host: String
    let port: Int
  }
  
  final class InitialRequestHandler: ChannelInboundHandler, RemovableChannelHandler {
    
    public typealias InboundIn = HTTPClientResponsePart
    public typealias OutboundOut = HTTPClientRequestPart
    
    public let target: ConnectTo
    
    public init(
      target: ConnectTo
    ) {
      self.target = target
    }
    
    public func channelActive(
      context: ChannelHandlerContext
    ) {
      log("active", "unwrap \(Self.InboundIn.self)")
      // We are connected. It's time to send the message to the server to initialize the upgrade dance.
      let requestHead = HTTPRequestHead(
        version: .http1_1,
        method: .GET,
        uri: "/",
        headers: .init(
          [
            ("Host", "\(target.host):\(target.port)"),
            ("Content-Type", "text/plain; charset=utf-8"),
            ("Content-Length", "\(0)")
          ]
        )
      )
      context.write(
        self.wrapOutboundOut(
          .head(requestHead)
        ),
        promise: nil
      )
      
      let body = HTTPClientRequestPart.body(
        .byteBuffer(ByteBuffer())
      )
      context.write(
        self.wrapOutboundOut(body),
        promise: nil
      )
      context.writeAndFlush(
        self.wrapOutboundOut(.end(nil)),
        promise: nil
      )
    }
    
    public func channelRead(
      context: ChannelHandlerContext,
      data: NIOAny
    ) {
      log("read", "unwrap \(Self.InboundIn.self)")
      let clientResponse = self.unwrapInboundIn(data)
      
      switch clientResponse {
        case .head(let responseHead):
          print("Received status: \(responseHead.status)")
        case .body(let byteBuffer):
          let string = String(buffer: byteBuffer)
          print("Received: '\(string)' back from the server.")
        case .end:
          print("Closing channel.")
          context.close(promise: nil)
      }
    }
    
    public func handlerRemoved(
      context: ChannelHandlerContext
    ) {
      print("HTTP handler removed.")
    }
    
    public func errorCaught(
      context: ChannelHandlerContext,
      error: Error
    ) {
      print("error: ", error)
      
      // As we are not really interested getting notified on success or failure
      // we just pass nil as promise to reduce allocations.
      context.close(promise: nil)
    }
  }
  
  final class MessageOutboundHandler: ChannelOutboundHandler {
    
    typealias OutboundIn = WireEnvelope
    typealias OutboundOut = WebSocketFrame
    
    let actorSystem: ClientServerActorSystem
    
    init(
      actorSystem: ClientServerActorSystem
    ) {
      self.actorSystem = actorSystem
    }
    
    public func handlerRemoved(context: ChannelHandlerContext) {
      // While we do this, we should also notify the system about any cleanups
      // it might need to do. E.g. if it has receptionist connections to the peer
      // that has now disconnected, we should stop tasks interacting with it etc.
      print("WebSocket handler removed.")
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
      log("write", "unwrap \(Self.OutboundIn.self)")
      let envelope: WireEnvelope = self.unwrapOutboundIn(data)
      
      switch envelope {
        case .connectionClose:
          var data = context.channel
            .allocator
            .buffer(capacity: 2)
          data.write(
            webSocketErrorCode: .protocolError
          )
          let frame = WebSocketFrame(
            fin: true,
            opcode: .connectionClose,
            data: data
          )
          context.writeAndFlush(
            self.wrapOutboundOut(frame)
          ).whenComplete { (_: Result<Void, Error>) in
            context.close(promise: nil)
          }
        case .reply, .call:
          let encoder = JSONEncoder()
          encoder.userInfo[.actorSystemKey] = actorSystem
          
          var data = ByteBuffer()
          _ = try? data.writeJSONEncodable(
            envelope,
            encoder: encoder
          )
          log("outbound-call", "Write: \(envelope), to: \(context)")
          
          let frame = WebSocketFrame(
            fin: true,
            opcode: .text,
            data: data
          )
          context.writeAndFlush(
            self.wrapOutboundOut(frame),
            promise: nil
          )
          //        log("outbound-call", "Failed to serialize call [\(envelope)], error: \(error)")
      }
    }
  }
  
  // ===== --------------------------------------------------------------------------------------------------------------
  // MARK: Server-side handlers
  
  final class HTTPHandler: ChannelInboundHandler, RemovableChannelHandler {
    
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    
    private var responseBody: ByteBuffer!
    
    func handlerAdded(context: ChannelHandlerContext) {
      self.responseBody = context.channel.allocator.buffer(string: "<html><head></head><body><h2>Test WS Server System</h2></body></html>")
    }
    
    func handlerRemoved(context: ChannelHandlerContext) {
      self.responseBody = nil
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
      log("read", "unwrap \(Self.InboundIn.self)")
      let reqPart = self.unwrapInboundIn(data)
      
      // We're not interested in request bodies here: we're just serving up GET responses
      // to get the client to initiate a websocket request.
      guard case .head(let head) = reqPart else {
        return
      }
      
      // GETs only.
      guard case .GET = head.method else {
        self.respond405(context: context)
        return
      }
      
      var headers = HTTPHeaders()
      headers.add(name: "Content-Type", value: "text/html")
      headers.add(name: "Content-Length", value: String(self.responseBody.readableBytes))
      headers.add(name: "Connection", value: "close")
      let responseHead = HTTPResponseHead(version: .init(major: 1, minor: 1),
                                          status: .ok,
                                          headers: headers)
      context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
      context.write(self.wrapOutboundOut(.body(.byteBuffer(self.responseBody))), promise: nil)
      context.write(self.wrapOutboundOut(.end(nil))).whenComplete { (_: Result<Void, Error>) in
        context.close(promise: nil)
      }
      context.flush()
    }
    
    private func respond405(context: ChannelHandlerContext) {
      var headers = HTTPHeaders()
      headers.add(name: "Connection", value: "close")
      headers.add(name: "Content-Length", value: "0")
      let head = HTTPResponseHead(version: .http1_1,
                                  status: .methodNotAllowed,
                                  headers: headers)
      context.write(self.wrapOutboundOut(.head(head)), promise: nil)
      context.write(self.wrapOutboundOut(.end(nil))).whenComplete { (_: Result<Void, Error>) in
        context.close(promise: nil)
      }
      context.flush()
    }
  }
  
  final class ActorMessageInboundHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WireEnvelope
    
    private var awaitingClose: Bool = false
    
    private let actorSystem: ClientServerActorSystem
    init(actorSystem: ClientServerActorSystem) {
      self.actorSystem = actorSystem
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
      log("read", "unwrap \(Self.InboundIn.self)")
      let frame = self.unwrapInboundIn(data)
      
      switch frame.opcode {
        case .connectionClose:
          // Close the connection.
          //
          // We might also want to inform the actor system that this connection
          // went away, so it can terminate any tasks or actors working to
          // inform the remote receptionist on the now-gone system about our
          // actors.
          return
        case .text:
          var data = frame.unmaskedData
          let text = data.getString(at: 0, length: data.readableBytes) ?? ""
          log("inbound-call", "Received: \(text), from: \(context)")
          
          try? actorSystem
            .decodeAndDeliver(
              data: &data,
              from: context.remoteAddress,
              on: context.channel
            )
          
        case .binary, .continuation, .pong, .ping:
          // We ignore these frames.
          break
        default:
          // Unknown frames are errors.
          self.closeOnError(context: context)
      }
    }
    
    public func channelReadComplete(context: ChannelHandlerContext) {
      context.flush()
    }
    
    private func receivedClose(context: ChannelHandlerContext, frame: WebSocketFrame) {
      // Handle a received close frame. In websockets, we're just going to send the close
      // frame and then close, unless we already sent our own close frame.
      if awaitingClose {
        // Cool, we started the close and were waiting for the user. We're done.
        context.close(promise: nil)
      } else {
        // This is an unsolicited close. We're going to send a response frame and
        // then, when we've sent it, close up shop. We should send back the close code the remote
        // peer sent us, unless they didn't send one at all.
        _ = context.write(self.wrapOutboundOut(.connectionClose)).map { () in
          context.close(promise: nil)
        }
      }
    }
    
    private func closeOnError(context: ChannelHandlerContext) {
      // We have hit an error, we want to close. We do that by sending a close frame and then
      // shutting down the write side of the connection.
      var data = context.channel.allocator.buffer(capacity: 2)
      data.write(webSocketErrorCode: .protocolError)
      
      context.write(self.wrapOutboundOut(.connectionClose)).whenComplete { (_: Result<Void, Error>) in
        context.close(mode: .output, promise: nil)
      }
      
      awaitingClose = true
    }
  }
  
}

@available(iOS 16.0, *)
extension ClientServerActorSystem {
  func decodeAndDeliver(
    data: inout ByteBuffer,
    from address: SocketAddress?,
    on channel: NIOCore.Channel
  ) throws {
    let decoder = JSONDecoder()
    decoder.userInfo[.actorSystemKey] = self
    
    let wireEnvelope = try data.readJSONDecodable(WireEnvelope.self, length: data.readableBytes)
    
    switch wireEnvelope {
      case .call(let remoteCallEnvelope):
         log("receive-decode-deliver", "Decode remoteCall...")
        try self.receiveInboundCall(envelope: remoteCallEnvelope, on: channel)
      case .reply(let replyEnvelope):
        self.receiveInboundReply(envelope: replyEnvelope, on: channel)
      case .none, .connectionClose:
        log("receive-decode-deliver", "[error] Failed decoding: \(data); decoded empty")
    }
    //
    //    do {
    //
    //    } catch {
    //      log("receive-decode-deliver", "[error] Failed decoding: \(data), error: \(error)")
    //    }
    //    log("decode-deliver", "here...")
  }
  
  func receiveInboundCall(
    envelope: CallEnvelope,
    on channel: NIOCore.Channel
  ) throws {
    log("receive-inbound", "Envelope: \(envelope)")
    Task {
      log("receive-inbound", "Resolve any: \(envelope.recipient)")
      guard let anyRecipient = resolveAny(id: envelope.recipient, resolveReceptionist: true) else {
        log("deadLetter", "[warn] \(#function) failed to resolve \(envelope.recipient)")
        return
      }
      log("receive-inbound", "Recipient: \(anyRecipient)")
      let target = RemoteCallTarget(envelope.invocationTarget)
      log("receive-inbound", "Target: \(target)")
      log("receive-inbound", "Target.identifier: \(target.identifier)")
      let handler = ResultHandler(
        actorSystem: self,
        callID: envelope.callID,
        system: self,
        channel: channel
      )
      log("receive-inbound", "Handler: \(anyRecipient)")
      
      do {
        var decoder = Self.InvocationDecoder(system: self, envelope: envelope)
        func doExecuteDistributedTarget<Act: DistributedActor>(recipient: Act) async throws {
          log("receive-inbound", "executeDistributedTarget")
          try await executeDistributedTarget(
            on: recipient,
            target: target,
            invocationDecoder: &decoder,
            handler: handler
          )
        }
        
        // As implicit opening of existential becomes part of the language,
        // this underscored feature is no longer necessary. Please refer to
        // SE-352 Implicitly Opened Existentials:
        // https://github.com/apple/swift-evolution/blob/main/proposals/0352-implicit-open-existentials.md
        try await _openExistential(anyRecipient, do: doExecuteDistributedTarget)
      } catch {
        log("inbound", "[error] failed to executeDistributedTarget [\(target)] on [\(anyRecipient)], error: \(error)")
        try! await handler.onThrow(error: error)
      }
    }
  }
  
  func receiveInboundReply(
    envelope: ReplyEnvelope,
    on channel: NIOCore.Channel
  ) {
    log("receive-reply", "Reply envelope: \(envelope)")
    self.replyLock.lock()
    log("receive-reply", "Reply envelope delivering...: \(envelope)")
    
    guard let callContinuation = self.inFlightCalls.removeValue(forKey: envelope.callID) else {
      log("receive-reply", "Missing continuation for call \(envelope.callID); Envelope: \(envelope)")
      self.replyLock.unlock()
      return
    }
    
    self.replyLock.unlock()
    log("receive-reply", "Reply envelope delivering... RESUME: \(envelope)")
    callContinuation.resume(returning: envelope.value)
  }
}

extension ClientServerActorSystem {
  @available(iOS 16.0, *)
  public class NIOInvocationDecoder: DistributedTargetInvocationDecoder {
    
    public typealias SerializationRequirement = any Codable
    
    let decoder: JSONDecoder
    let envelope: CallEnvelope
    var argumentsIterator: Array<Data>.Iterator
    
    public init(
      system: ClientServerActorSystem,
      envelope: CallEnvelope
    ) {
      self.envelope = envelope
      self.argumentsIterator = envelope.args.makeIterator()
      
      let decoder = JSONDecoder()
      decoder.userInfo[.actorSystemKey] = system
      self.decoder = decoder
    }
    
    public func decodeGenericSubstitutions() throws -> [Any.Type] {
      return envelope.genericSubs.compactMap { name in
        return _typeByName(name)
      }
    }
    
    public func decodeNextArgument<Argument: Codable>() throws -> Argument {
      guard let data = argumentsIterator.next() else {
        log("decode-argument", "none left")
        throw SystemError.notEnoughArgumentsInEnvelope(expected: Argument.self)
      }
      
      let value = try decoder.decode(Argument.self, from: data)
      //    log("decode-argument", "decoded: \(value)")
      return value
    }
    
    public func decodeErrorType() throws -> Any.Type? {
      nil // not encoded, ok
    }
    
    public func decodeReturnType() throws -> Any.Type? {
      nil // not encoded, ok
    }
  }
}

public extension ClientServerActorSystem {
  enum SystemError: Error, DistributedActorSystemError {
    case resolveFailedToMatchActorType(found: Any.Type, expected: Any.Type)
    case noPeers
    case notEnoughArgumentsInEnvelope(expected: Any.Type)
    case failedDecodingResponse(data: Data, error: Error)
    case decodingError(error: Error)
    case resolveFailed(id: ClientServerActorSystem.ActorID)
  }
}

// TODO: Remove
extension String: Error {}

public extension ClientServerActorSystem {
  @available(iOS 16.0, *)
  class NIOInvocationEncoder: DistributedTargetInvocationEncoder {
    public typealias SerializationRequirement = any Codable
    var genericSubs: [String] = []
    var argumentData: [Data] = []
    
    public func recordGenericSubstitution<T>(_ type: T.Type) throws {
      if let name = _mangledTypeName(T.self) {
        genericSubs.append(name)
      }
    }
    
    public func recordArgument<Value: Codable>(_ argument: RemoteCallArgument<Value>) throws {
      let data = try JSONEncoder().encode(argument.value)
      self.argumentData.append(data)
    }
    
    public func recordReturnType<R: Codable>(_ type: R.Type) throws {
      // noop, no need to record it in this system
    }
    
    public func recordErrorType<E: Error>(_ type: E.Type) throws {
      // noop, no need to record it in this system
    }
    
    public func doneRecording() throws {
      // noop, nothing to do in this system
    }
  }
}

extension ClientServerActorSystem {
  
  /// We make up an ID for the remote bot; We know they are resolved and created on-demand
  public func actorId<V>(
    of type: V.Type,
    id: String
  ) -> ActorIdentity
  {
    .full(
      id: .init(
        type: String(describing: type.self),
        id: id
      ),
      protocol: mode.`protocol`,
      host: mode.host,
      port: mode.port
    )
  }
  
  public func registerOnDemandResolveHandler(
    resolveOnDemand: @escaping (ActorID) -> (any DistributedActor)?
  ) {
    lock.lock()
    defer {
      self.lock.unlock()
    }
    self.resolveOnDemandHandler = resolveOnDemand
  }
  
  public func makeActorWithID<Act>(
    _ id: ActorID,
    _ factory: () -> Act
  ) -> Act
  where Act: DistributedActor, Act.ActorSystem == ClientServerActorSystem
  {
    Self.$actorIDHint.withValue(id) {
      factory()
    }
  }
}
