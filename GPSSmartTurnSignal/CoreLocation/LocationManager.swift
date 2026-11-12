import Foundation
import CoreLocation
import Combine

/// Chất lượng tín hiệu GPS thực tế
public enum GPSSignalQuality: String {
    case none = "Mất tín hiệu"
    case poor = "Yếu (>20m)"
    case good = "Tốt (10-20m)"
    case excellent = "Rất chính xác (<10m)"
    
    public var colorName: String {
        switch self {
        case .none: return "red"
        case .poor: return "orange"
        case .good: return "yellow"
        case .excellent: return "green"
        }
    }
}

/// Trình quản lý GPS nền và tọa độ thời gian thực của thiết bị
public final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    public static let shared = LocationManager()
    
    private let locationManager = CLLocationManager()
    
    // MARK: - Published Properties
    @Published public var currentLocation: CLLocation?
    @Published public var currentCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8544)
    @Published public var currentSpeedKmh: Double = 0.0
    @Published public var currentCourse: Double = 0.0
    @Published public var instantCourse: Double = 0.0 // Góc tức thời không qua làm trễ để phát hiện rẽ ngay
    @Published public var horizontalAccuracy: Double = -1.0
    @Published public var signalQuality: GPSSignalQuality = .none
    @Published public var isAuthorized: Bool = false
    @Published public var isNavigatingBackground: Bool = false
    
    // Lọc nhẹ chỉ 2 mẫu để xoay bản đồ mượt mà không làm trễ góc lái
    private var recentCourses: [Double] = []
    private let courseWindowSize = 2
    private var previousLocation: CLLocation?
    
    public override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .automotiveNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone // Cập nhật tức thì liên tục không trễ mét nào
        
        // Hỗ trợ chạy ngầm tối đa cho ứng dụng dẫn đường
        locationManager.pausesLocationUpdatesAutomatically = false
        if #available(iOS 9.0, *) {
            locationManager.allowsBackgroundLocationUpdates = true
        }
        if #available(iOS 11.0, *) {
            locationManager.showsBackgroundLocationIndicator = true
        }
        
        checkAuthorization()
    }
    
    /// Yêu cầu cấp quyền định vị
    public func requestPermissions() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        } else if locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        }
    }
    
    /// Bắt đầu theo dõi vị trí GPS
    public func startTracking() {
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        isNavigatingBackground = true
    }
    
    /// Dừng theo dõi vị trí GPS
    public func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        isNavigatingBackground = false
    }
    
    private func checkAuthorization() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isAuthorized = true
        default:
            isAuthorized = false
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkAuthorization()
        if isAuthorized {
            startTracking()
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Tốc độ di chuyển (chuyển đổi từ m/s sang km/h)
        if location.speed >= 0 {
            currentSpeedKmh = max(0, location.speed * 3.6)
        } else if let prev = previousLocation {
            let dt = location.timestamp.timeIntervalSince(prev.timestamp)
            if dt > 0.1 {
                let dist = location.distance(from: prev)
                currentSpeedKmh = (dist / dt) * 3.6
            }
        }
        
        // Góc di chuyển tức thời (Instant Course) không qua độ trễ
        if location.course >= 0 {
            instantCourse = location.course
            updateSmoothedCourse(newCourse: location.course)
        } else if let prev = previousLocation, location.distance(from: prev) >= 1.5 {
            let bearing = calculateBearing(from: prev.coordinate, to: location.coordinate)
            instantCourse = bearing
            updateSmoothedCourse(newCourse: bearing)
        }
        
        previousLocation = location
        currentCoordinate = location.coordinate
        currentLocation = location
        
        // Đánh giá độ chính xác ngang của tín hiệu GPS
        horizontalAccuracy = location.horizontalAccuracy
        if location.horizontalAccuracy < 0 {
            signalQuality = .none
        } else if location.horizontalAccuracy <= 10 {
            signalQuality = .excellent
        } else if location.horizontalAccuracy <= 20 {
            signalQuality = .good
        } else {
            signalQuality = .poor
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Nếu xe đang đứng yên hoặc đi rất chậm, dùng la bàn điện tử phản hồi tức thì
        if currentSpeedKmh < 5.0 && newHeading.trueHeading >= 0 && newHeading.headingAccuracy > 0 {
            instantCourse = newHeading.trueHeading
            updateSmoothedCourse(newCourse: newHeading.trueHeading)
        }
    }
    
    private func calculateBearing(from start: CLLocationCoordinate2D, to dest: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180.0
        let lon1 = start.longitude * .pi / 180.0
        let lat2 = dest.latitude * .pi / 180.0
        let lon2 = dest.longitude * .pi / 180.0
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        return (radians * 180.0 / .pi + 360.0).truncatingRemainder(dividingBy: 360.0)
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("CoreLocation error: \(error.localizedDescription)")
    }
    
    /// Làm mịn góc di chuyển bằng trung bình trượt góc vòng tròn
    private func updateSmoothedCourse(newCourse: Double) {
        recentCourses.append(newCourse)
        if recentCourses.count > courseWindowSize {
            recentCourses.removeFirst()
        }
        
        var sinSum: Double = 0
        var cosSum: Double = 0
        for angle in recentCourses {
            let rad = angle * .pi / 180.0
            sinSum += sin(rad)
            cosSum += cos(rad)
        }
        
        var avgRad = atan2(sinSum, cosSum)
        if avgRad < 0 { avgRad += 2 * .pi }
        currentCourse = avgRad * 180.0 / .pi
    }
}
