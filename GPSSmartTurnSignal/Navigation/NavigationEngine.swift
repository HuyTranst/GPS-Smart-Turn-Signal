import Foundation
import CoreLocation
import Combine

/// Động cơ phân tích dẫn đường và nhận diện nút giao rẽ xi nhan thông minh
public final class NavigationEngine: ObservableObject {
    public static let shared = NavigationEngine()
    
    // MARK: - Published Properties
    @Published public var isNavigating: Bool = false
    @Published public var activeRoute: NavigationRoute?
    @Published public var currentManeuver: RouteManeuver?
    @Published public var distanceToNextManeuver: Double = 0.0 // Mét
    @Published public var remainingTripDistance: Double = 0.0 // Mét
    @Published public var isOffRoute: Bool = false
    @Published public var simulationActive: Bool = false
    
    private let locationManager = LocationManager.shared
    private let turnController = TurnSignalController.shared
    private let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Timer mô phỏng GPS chạy thử khi đứng yên
    private var simulationTimer: Timer?
    private var simulationIndex: Int = 0
    
    private init() {
        locationManager.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.processLocationUpdate(location)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Route Controls
    
    /// Bắt đầu hành trình dẫn đường
    public func startNavigation(route: NavigationRoute) {
        var mutableRoute = route
        // Reset trạng thái các nút giao
        for i in 0..<mutableRoute.maneuvers.count {
            mutableRoute.maneuvers[i].isTriggered = false
            mutableRoute.maneuvers[i].isCompleted = false
        }
        
        self.activeRoute = mutableRoute
        self.isNavigating = true
        self.currentManeuver = mutableRoute.maneuvers.first
        self.remainingTripDistance = mutableRoute.totalDistanceMeters
        
        locationManager.startTracking()
        print("Navigation started: \(route.title)")
    }
    
    /// Kết thúc hành trình dẫn đường
    public func stopNavigation() {
        isNavigating = false
        activeRoute = nil
        currentManeuver = nil
        distanceToNextManeuver = 0
        remainingTripDistance = 0
        stopSimulation()
        turnController.turnOff()
        print("Navigation stopped")
    }
    
    // MARK: - GPS Analysis & Turn Detection Logic
    
    private func processLocationUpdate(_ location: CLLocation) {
        guard isNavigating, var route = activeRoute else { return }
        
        // 1. Tìm ngã rẽ tiếp theo chưa hoàn thành
        guard let maneuverIndex = route.maneuvers.firstIndex(where: { !$0.isCompleted }) else {
            // Đã đi qua hết tất cả các nút giao -> Kết thúc chuyến đi
            stopNavigation()
            return
        }
        
        var maneuver = route.maneuvers[maneuverIndex]
        self.currentManeuver = maneuver
        
        // 2. Tính khoảng cách địa lý thực tế từ xe đến ngã rẽ
        let maneuverLoc = CLLocation(latitude: maneuver.point.latitude, longitude: maneuver.point.longitude)
        let distance = location.distance(from: maneuverLoc)
        self.distanceToNextManeuver = distance
        
        // 3. Tính góc phương vị từ xe hướng tới giao lộ
        let bearingToJunction = calculateBearing(from: location.coordinate, to: maneuverLoc.coordinate)
        let vehicleCourse = locationManager.currentCourse
        let speedKmh = locationManager.currentSpeedKmh
        
        // Góc lệch giữa hướng đầu xe và hướng tới giao lộ (đảm bảo xe đang tiến lại gần, không phải đi ra xa)
        let angleDiff = abs(normalizeAngle(vehicleCourse - bearingToJunction))
        
        // 4. KIỂM TRA ĐIỀU KIỆN KÍCH HOẠT XI NHAN
        // Tiêu chí chống báo sai theo yêu cầu khắt khe của dự án:
        // - Khoảng cách nằm trong ngưỡng cấu hình (ví dụ <= 80m)
        // - Nút giao chưa từng được kích hoạt trước đó
        // - Tốc độ GPS đạt mức tối thiểu (ví dụ >= 10 km/h) để loại bỏ sai số khi đứng yên hoặc chỉnh giá đỡ điện thoại
        // - Góc bẻ lái của tuyến đường phải đủ lớn (ví dụ >= 45 độ) để phân biệt ngã rẽ thật với đường cong uốn lượn
        // - Xe thực sự đang hướng về giao lộ (angleDiff <= 55 độ)
        let isWithinTriggerDistance = distance <= settings.triggerDistanceMeters && distance >= 8.0
        let isSpeedValid = speedKmh >= settings.minSpeedKmh
        let isTurnAngleSignificant = abs(maneuver.turnAngleDegrees) >= settings.turnSensitivityDegrees
        let isHeadingTowardJunction = angleDiff <= 55.0
        
        if !maneuver.isTriggered && isWithinTriggerDistance && isSpeedValid && isTurnAngleSignificant && isHeadingTowardJunction {
            // Đánh dấu đã kích hoạt
            maneuver.isTriggered = true
            route.maneuvers[maneuverIndex] = maneuver
            self.activeRoute = route
            
            let isLeft = maneuver.type.isTurnLeft
            print(">>> KÍCH HOẠT XI NHAN \(isLeft ? "TRÁI" : "PHẢI") tại khoảng cách \(Int(distance))m, góc rẽ: \(maneuver.turnAngleDegrees)°")
            turnController.triggerNavigationTurn(isLeft: isLeft, distanceToJunction: distance)
        }
        
        // 5. KIỂM TRA ĐIỀU KIỆN HOÀN THÀNH RẼ (TỰ TẮT XI NHAN)
        // Xe đã vượt qua ngã rẽ (khoảng cách <= 12m hoặc xe đã đi qua và đang hướng theo đoạn đường mới)
        if maneuver.isTriggered && (distance <= 12.0 || (distance < 25.0 && angleDiff > 90.0)) {
            maneuver.isCompleted = true
            route.maneuvers[maneuverIndex] = maneuver
            self.activeRoute = route
            
            print("<<< ĐÃ QUA NGÃ RẼ -> Tắt xi nhan")
            turnController.turnOff()
            
            // Chuyển sang nút giao tiếp theo
            if maneuverIndex + 1 < route.maneuvers.count {
                self.currentManeuver = route.maneuvers[maneuverIndex + 1]
            }
        }
    }
    
    // MARK: - Mathematical Geodesic Helpers
    
    /// Tính góc phương vị từ điểm A đến điểm B (0 - 360 độ)
    private func calculateBearing(from start: CLLocationCoordinate2D, to dest: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180.0
        let lon1 = start.longitude * .pi / 180.0
        let lat2 = dest.latitude * .pi / 180.0
        let lon2 = dest.longitude * .pi / 180.0
        
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        let degrees = (radians * 180.0 / .pi + 360.0).truncatingRemainder(dividingBy: 360.0)
        return degrees
    }
    
    /// Chuẩn hóa góc về khoảng -180 đến +180 độ
    private func normalizeAngle(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 360.0)
        if a > 180.0 { a -= 360.0 }
        if a < -180.0 { a += 360.0 }
        return a
    }
    
    // MARK: - Simulation Mode (Dành cho việc test trên bàn làm việc không cần chạy xe)
    
    /// Bắt đầu giả lập hành trình mẫu
    public func startSimulation(route: NavigationRoute) {
        stopSimulation()
        startNavigation(route: route)
        simulationActive = true
        simulationIndex = 0
        
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self, let activeRoute = self.activeRoute else { return }
            guard self.simulationIndex < activeRoute.points.count else {
                self.stopSimulation()
                return
            }
            
            let pt = activeRoute.points[self.simulationIndex]
            let mockLoc = CLLocation(
                coordinate: pt.clLocationCoordinate2D,
                altitude: 10,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                course: 45.0,
                speed: 35.0 / 3.6, // 35 km/h
                timestamp: Date()
            )
            
            self.locationManager.locationManager(CLLocationManager(), didUpdateLocations: [mockLoc])
            self.simulationIndex += 1
        }
    }
    
    /// Dừng mô phỏng
    public func stopSimulation() {
        simulationTimer?.invalidate()
        simulationTimer = nil
        simulationActive = false
    }
}
