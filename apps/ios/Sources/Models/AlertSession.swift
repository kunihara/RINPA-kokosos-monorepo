import Foundation

struct AlertSession: Codable, Equatable {
    enum Status: String, Codable { case active, ended, revoked }
    enum Mode: String, Codable { case emergency, going_home }
    let id: String
    let shareToken: String
    var status: Status
    let mode: Mode
}
