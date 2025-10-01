import Foundation

struct AlertSession: Codable, Equatable {
    enum Status: String, Codable { case active, ended, revoked }
    let id: String
    let shareToken: String
    var status: Status
}
