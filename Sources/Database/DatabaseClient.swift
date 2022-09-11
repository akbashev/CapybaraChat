import GRDB
import Foundation

public struct DatabaseClient {
  public let users: UserDatabaseClient
  public let rooms: RoomDatabaseClient
}

// TODO: Add Vapor Fluent example
extension DatabaseClient {
  public static func memory() async throws -> DatabaseClient {
    let dbQueue = try DatabaseQueue()
    try await DatabaseClient.createTable(dbQueue)
    return DatabaseClient.grdb(dbQueue)
  }
  
  public static func live(path: String) async throws -> DatabaseClient {
    let dbQueue = try DatabaseQueue(path: path)
    try await DatabaseClient.createTable(dbQueue)
    return DatabaseClient.grdb(dbQueue)
  }
  
  private static func grdb(
    _ dbQueue: DatabaseQueue
  ) -> DatabaseClient {
    DatabaseClient(
      users: .grdb(dbQueue),
      rooms: .grdb(dbQueue)
    )
  }
  
  @discardableResult
  private static func createTable(_ dbQueue: DatabaseQueue) async throws -> DatabaseQueue {
    try await dbQueue.write { db in
      if try db.tableExists("room") == false {
        try db.create(table: "room") { t in
          t.autoIncrementedPrimaryKey("id")
          t.column("name", .text).notNull()
        }
      }
      if try db.tableExists("user") == false {
        try db.create(table: "user") { t in
          t.autoIncrementedPrimaryKey("id")
          t.column("name", .text).notNull()
        }
      }
      if try db.tableExists("userRoom") == false {
        try db.create(table: "userRoom") { t in
          t.column("status", .integer).notNull()
          t.column("userId", .integer)
            .notNull()
            .indexed()
            .references("user", onDelete: .cascade)
          t.column("roomId", .integer)
            .notNull()
            .indexed()
            .references("room", onDelete: .cascade)
        }
      }
      if try db.tableExists("message") == false {
        try db.create(table: "message") { t in
          t.autoIncrementedPrimaryKey("id")
          t.column("text", .text).notNull()
          t.column("createdAt", .date).notNull()
          t.column("userId", .integer)
            .notNull()
            .indexed()
            .references("user", onDelete: .cascade)
          t.column("roomId", .integer)
            .notNull()
            .indexed()
            .references("room", onDelete: .cascade)
        }
      }
    }
    return dbQueue
  }
  
  // Migrate
  // private static func migrate(_ dbQueue: DatabaseQueue) {}
}
