import Foundation

final class SettingsStore {
    static let shared = SettingsStore()
    static let changedNotification = Notification.Name("kokosos.settings.changed")
    private init() {}

    private let keyArrivalReminder = "arrivalReminderMinutes"
    private let keyGoingHomeMax = "goingHomeMaxMinutes"
    private let keyRequireTripleTap = "requireTripleTapForStart"
    private let keyEnableDebugSimulation = "enableDebugSimulation"
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

    // 開始操作の安全性: 3回タップ(既定) or 1回タップ
    var requireTripleTap: Bool {
        get {
            if UserDefaults.standard.object(forKey: keyRequireTripleTap) == nil {
                return true // 既定: 3回タップを要求
            }
            return UserDefaults.standard.bool(forKey: keyRequireTripleTap)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: keyRequireTripleTap)
            NotificationCenter.default.post(name: SettingsStore.changedNotification, object: nil)
        }
    }

    #if DEBUG
    // デバッグ用: 開始/停止を通信せず擬似成功/失敗で検証
    var enableDebugSimulation: Bool {
        get { UserDefaults.standard.bool(forKey: keyEnableDebugSimulation) }
        set {
            UserDefaults.standard.set(newValue, forKey: keyEnableDebugSimulation)
            NotificationCenter.default.post(name: SettingsStore.changedNotification, object: nil)
        }
    }
    #else
    var enableDebugSimulation: Bool { get { return false } set { /* no-op */ } }
    #endif

    // apiBaseURLOverride は削除済み
}
