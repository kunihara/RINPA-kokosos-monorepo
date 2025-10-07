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
}

// Foreground notification presentation (banner/sound)
extension AppDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .list])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}

// Firebase Messaging token updates
extension AppDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken, !token.isEmpty else { return }
        PushRegistrationService.shared.register(token: token)
    }
}
