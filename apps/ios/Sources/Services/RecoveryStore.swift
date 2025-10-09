import Foundation

final class RecoveryStore {
    static let shared = RecoveryStore()
    private init() {}

    // 最後に受け取ったリカバリ（パスワード再設定）用の情報を保持
    var email: String?
    var token: String?

    func set(email: String?, token: String?) {
        self.email = (email?.isEmpty == false) ? email : nil
        self.token = (token?.isEmpty == false) ? token : nil
    }
    func clear() {
        email = nil
        token = nil
    }
}

