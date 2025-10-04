import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    completion(granted)
                }
            case .denied:
                completion(false)
            default:
                completion(true)
            }
        }
    }

    func scheduleArrivalReminder(after seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "到着リマインダー"
        content.body = "到着したら『停止』をタップしてください。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let req = UNNotificationRequest(identifier: "arrival_reminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func cancelArrivalReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["arrival_reminder"])
    }
}

