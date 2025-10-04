import UIKit

enum DeepLinkHandler {
    /// Handle custom URL scheme callback like:
    /// kokosos(-dev)://oauth-callback#access_token=...&refresh_token=...&expires_in=3600&token_type=bearer&type=signup
    @discardableResult
    static func handle(url: URL, in navigation: UINavigationController?) -> Bool {
        guard let host = url.host?.lowercased(), host == "oauth-callback" else { return false }
        // Parse fragment as query parameters
        let fragment = url.fragment ?? ""
        var params: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map { String($0) }
            if kv.count == 2 {
                params[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
            }
        }
        guard let access = params["access_token"], !access.isEmpty else { return false }
        // Save token for APIClient
        APIClient().setAuthToken(access)
        // Navigate to Main
        if let nav = navigation {
            let main = MainViewController()
            nav.setViewControllers([main], animated: true)
        }
        return true
    }
}

