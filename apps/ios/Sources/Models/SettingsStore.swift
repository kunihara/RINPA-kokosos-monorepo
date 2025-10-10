import Foundation

final class SettingsStore {
    static let shared = SettingsStore()
    static let changedNotification = Notification.Name("kokosos.settings.changed")
    private init() {}

    private let keyArrivalReminder = "arrivalReminderMinutes"
    private let keyGoingHomeMax = "goingHomeMaxMinutes"
    // APIベースURLの上書きは廃止

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

    var goingHomeMaxMinutes: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: keyGoingHomeMax)
            return v > 0 ? v : 120 // 既定120分
        }
        set {
            // 30〜240分の範囲に制限
            let clamped = max(30, min(newValue, 240))
            UserDefaults.standard.set(clamped, forKey: keyGoingHomeMax)
            NotificationCenter.default.post(name: SettingsStore.changedNotification, object: nil)
        }
    }

    // apiBaseURLOverride は削除済み
}
