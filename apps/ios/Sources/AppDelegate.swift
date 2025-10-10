import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        // Firebase
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        // Local/Push notifications: ensure delegate is set so foreground notifications can appear
        UNUserNotificationCenter.current().delegate = self
        // Ask notification permission on first launch (alert/sound/badge)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            #if DEBUG
            print("[Notifications] permission granted=\(granted)")
            #endif
        }
        // Register for remote notifications (permission prompt is handled elsewhere)
        DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        // Try to fetch FCM token and register to server
        Messaging.messaging().token { token, _ in
            if let t = token { PushRegistrationService.shared.register(token: t) }
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    // Explicitly forward APNs token to FCM (in case swizzling is disabled later)
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        // APNsトークン設定後に FCM トークンを再取得（初回起動などで未取得の取りこぼしを防ぐ）
        Messaging.messaging().token { token, _ in
            if let t = token { PushRegistrationService.shared.register(token: t) }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("[Notifications] APNs registration failed: \(error.localizedDescription)")
        #endif
    }
}

// Foreground notification presentation (banner/sound)
extension AppDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let cat = notification.request.content.categoryIdentifier
        if cat == "contacts" {
            NotificationCenter.default.post(name: Notification.Name("ContactsShouldRefresh"), object: nil)
        }
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .list])
        } else {
            completionHandler([.alert, .sound])
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let cat = response.notification.request.content.categoryIdentifier
        if cat == "contacts" {
            NotificationCenter.default.post(name: Notification.Name("ContactsShouldRefresh"), object: nil)
        }
        completionHandler()
    }
}

// Firebase Messaging token updates
extension AppDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken, !token.isEmpty else { return }
        PushRegistrationService.shared.register(token: token)
    }
}
