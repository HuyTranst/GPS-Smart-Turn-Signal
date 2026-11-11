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
    @Published public var horizontalAccuracy: Double = -1.0
    @Published public var signalQuality: GPSSignalQuality = .none
    @Published public var isAuthorized: Bool = false
    @Published public var isNavigatingBackground: Bool = false
    
    // Lọc làm mịn góc di chuyển (smoothing bearing)
    private var recentCourses: [Double] = []
    private let courseWindowSize = 5
    
    public override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .automotiveNavigation
        locationManager.distanceFilter = 2.0 // Cập nhật mỗi khi di chuyển 2m
        
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
        
        currentLocation = location
        currentCoordinate = location.coordinate
        
        // Tốc độ di chuyển (chuyển đổi từ m/s sang km/h)
        if location.speed >= 0 {
            currentSpeedKmh = max(0, location.speed * 3.6)
        } else {
            currentSpeedKmh = 0.0
        }
        
        // Góc di chuyển (Course / Bearing) kèm thuật toán lọc ổn định
        if location.course >= 0 {
            updateSmoothedCourse(newCourse: location.course)
        }
        
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
        // Nếu xe đang đứng yên hoặc tốc độ quá chậm, dùng la bàn từ trường
        if currentSpeedKmh < 3.0 && newHeading.trueHeading >= 0 {
            updateSmoothedCourse(newCourse: newHeading.trueHeading)
        }
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
