/**
 Don't know if I'll need all Vapor features or not, maybe just better to use pure SwiftNIO.
 But will use for a faster development now.
*/
import Vapor

@main
enum Server {
  static func main() async throws {
    var env = try Environment.detect()
    try LoggingSystem.bootstrap(from: &env)
    let app = Application(env)
    defer { app.shutdown() }
    // Configure
    try await configure(app)
    try app.run()
  }
}
