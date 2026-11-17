import CoreLocation
import Observation

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    var location: CLLocation?
    var authorization: CLAuthorizationStatus = .notDetermined

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 20
        authorization = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    func start() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if isAuthorized { manager.startUpdatingLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 定位失败时保持上一次位置即可
    }

    /// 到某点的直线距离（米）
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard let location else { return nil }
        return location.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}
