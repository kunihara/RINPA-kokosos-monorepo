import Foundation

final class SettingsStore {
    static let shared = SettingsStore()
    static let changedNotification = Notification.Name("kokosos.settings.changed")
    private init() {}

    private let keyArrivalReminder = "arrivalReminderMinutes"

    var arrivalReminderMinutes: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: keyArrivalReminder)
            return v > 0 ? v : 30
        }
        set {
            let clamped = max(5, min(newValue, 120))
            UserDefaults.standard.set(clamped, forKey: keyArrivalReminder)
            NotificationCenter.default.post(name: SettingsStore.changedNotification, object: nil)
        }
    }
}

