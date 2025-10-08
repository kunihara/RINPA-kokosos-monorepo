import Foundation
import CoreLocation

final class BackgroundLocationTracker: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let api = APIClient()
    private var alertId: String?
    private var lastSentAt: Date?
    private let minSendInterval: TimeInterval = 30 // 秒間隔の下限（過送信防止）

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .otherNavigation
    }

    func start(alertId: String) {
        self.alertId = alertId
        // 認可状態に応じて Always を要求
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // WhenInUse 許可後に delegate で requestAlways を続けて呼ぶ
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
        // 位置更新を開始（バックグラウンド許可がなくてもフォアグラウンドで動く）
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        alertId = nil
        lastSentAt = nil
    }

    // MARK: CLLocationManagerDelegate
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // WhenInUse → Always へ昇格要求（必要な場合）
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let id = alertId, let loc = locations.last else { return }
        // スロットリング
        let now = Date()
        if let last = lastSentAt, now.timeIntervalSince(last) < minSendInterval { return }
        lastSentAt = now
        let battery = LocationService.batteryPercent()
        Task.detached { [id, loc, battery, api] in
            do {
                try await api.updateAlert(id: id,
                                          lat: loc.coordinate.latitude,
                                          lng: loc.coordinate.longitude,
                                          accuracy: loc.horizontalAccuracy,
                                          battery: battery)
            } catch {
                // 送信失敗は無視（再送は次の更新で）
            }
        }
    }
}
