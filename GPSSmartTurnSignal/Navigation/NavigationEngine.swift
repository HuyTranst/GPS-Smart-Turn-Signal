import Foundation
import CoreLocation
import Combine

/// Động cơ nhận diện ngã rẽ thông minh tự động (Chế độ tự do không cần nhập tuyến đường)
public final class NavigationEngine: ObservableObject {
    public static let shared = NavigationEngine()
    
    // MARK: - Chế độ Giám sát Tự do (Free Ride Mode - Mặc định)
    @Published public var isAutoProtectActive: Bool = true
    @Published public var detectedTurnState: TurnSignalState = .off
    @Published public var currentTurnAngleDelta: Double = 0.0 // Góc bẻ lái so với hướng thẳng
    @Published public var baselineHeading: Double = 0.0 // Hướng thẳng làm mốc ban đầu
    @Published public var alertBannerText: String = "🛡️ Chế độ tự động bảo vệ: Đang canh chừng ngã rẽ"
    
    // MARK: - Chế độ Dẫn đường Lộ trình (Tùy chọn)
    @Published public var isNavigating: Bool = false
    @Published public var activeRoute: NavigationRoute?
    @Published public var currentManeuver: RouteManeuver?
    @Published public var distanceToNextManeuver: Double = 0.0
    @Published public var remainingTripDistance: Double = 0.0
    @Published public var isOffRoute: Bool = false
    @Published public var simulationActive: Bool = false
    
    private let locationManager = LocationManager.shared
    private let turnController = TurnSignalController.shared
    private let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Biến nội bộ thuật toán nhận diện rẽ tự do (Zero-Delay Sliding Window)
    private struct CourseSample {
        let timestamp: Date
        let course: Double
    }
    private var courseHistory: [CourseSample] = []
    private var hasEstablishedBaseline = false
    private var turnStartHeading: Double = 0.0
    private var turnStartTime: Date = Date.distantPast
    private var turnCompletionSteadyCount = 0
    private var lastRecordedCourse: Double = 0.0
    
    // Simulation Timer
    private var simulationTimer: Timer?
    private var simulationIndex: Int = 0
    
    private init() {
        startFreeRideProtection()
        
        locationManager.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.processLocationUpdate(location)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Khởi Động Chế Độ Tự Do
    
    /// Bật chế độ tự động canh ngã rẽ liên tục khi lái xe
    public func startFreeRideProtection() {
        isAutoProtectActive = true
        hasEstablishedBaseline = false
        courseHistory.removeAll()
        turnCompletionSteadyCount = 0
        locationManager.startTracking()
        print("Free-ride Auto Protection ACTIVE (Zero-Delay Mode)")
    }
    
    // MARK: - Xử Lý GPS Thời Gian Thực
    
    private func processLocationUpdate(_ location: CLLocation) {
        guard settings.isAutoSignalEnabled else { return }
        
        // NẾU CÓ TUYẾN ĐƯỜNG CỐ ĐỊNH -> CHẠY THUẬT TOÁN ĐIỂM GIAO LỘ
        if isNavigating, activeRoute != nil {
            processRouteManeuvers(location: location)
            return
        }
        
        // CHẾ ĐỘ TỰ DO (FREE RIDE - DÙNG HẰNG NGÀY KHÔNG CẦN CHỌN ĐƯỜNG):
        processFreeRideTurnDetection(location: location)
    }
    
    /// Thuật toán nhận diện bẻ lái TỨC THÌ (Vừa quẹo là bật liền, 0 độ trễ)
    private func processFreeRideTurnDetection(location: CLLocation) {
        let speed = locationManager.currentSpeedKmh
        let course = locationManager.instantCourse
        let now = Date()
        
        // 1. Nếu xe đứng yên hoàn toàn (< minSpeedKmh, mặc định 3 km/h): giữ nguyên trạng thái
        guard speed >= settings.minSpeedKmh else {
            return
        }
        
        // Lưu mẫu hướng vào lịch sử (chỉ giữ 8 giây gần nhất)
        courseHistory.append(CourseSample(timestamp: now, course: course))
        courseHistory.removeAll { now.timeIntervalSince($0.timestamp) > 8.0 }
        
        // 2. Khởi tạo mốc hướng đầu tiên khi xe vừa lăn bánh
        if !hasEstablishedBaseline {
            baselineHeading = course
            lastRecordedCourse = course
            hasEstablishedBaseline = true
            alertBannerText = "🛡️ Đang giám sát ngã rẽ tức thì..."
            return
        }
        
        // 3. KHI CHƯA BẬT XI NHAN (ĐANG ĐI THẲNG):
        if turnController.currentState == .off {
            // Lấy các mẫu hướng cách đây từ 1.5 giây đến 5.0 giây (lúc xe chưa vào cua)
            // KHÔNG kéo baseline chạy theo góc cua nhẹ, nhờ vậy vừa bẻ lái 14° là phát hiện ngay trong 0.3s!
            let pastSamples = courseHistory.filter {
                let age = now.timeIntervalSince($0.timestamp)
                return age >= 1.5 && age <= 5.0
            }
            
            let referenceHeading: Double
            if !pastSamples.isEmpty {
                referenceHeading = circularMean(angles: pastSamples.map { $0.course })
            } else if let oldest = courseHistory.first {
                referenceHeading = oldest.course
            } else {
                referenceHeading = baselineHeading
            }
            
            baselineHeading = referenceHeading
            let delta = normalizeAngle(course - referenceHeading)
            self.currentTurnAngleDelta = delta
            
            // PHÁT HIỆN BẮT ĐẦU RẼ PHẢI NGAY LẬP TỨC:
            if delta >= settings.turnSensitivityDegrees {
                turnStartHeading = referenceHeading
                turnStartTime = now
                turnCompletionSteadyCount = 0
                detectedTurnState = .right
                alertBannerText = "🚨 ĐANG RẼ PHẢI - ĐÃ BẬT XI NHAN PHẢI!"
                print(">>> TỰ ĐỘNG BẬT XI NHAN PHẢI TỨC THÌ (Delta: +\(Int(delta))°, Speed: \(Int(speed))km/h)")
                turnController.triggerNavigationTurn(isLeft: false, distanceToJunction: 0)
            }
            // PHÁT HIỆN BẮT ĐẦU RẼ TRÁI NGAY LẬP TỨC:
            else if delta <= -settings.turnSensitivityDegrees {
                turnStartHeading = referenceHeading
                turnStartTime = now
                turnCompletionSteadyCount = 0
                detectedTurnState = .left
                alertBannerText = "🚨 ĐANG RẼ TRÁI - ĐÃ BẬT XI NHAN TRÁI!"
                print(">>> TỰ ĐỘNG BẬT XI NHAN TRÁI TỨC THÌ (Delta: \(Int(delta))°, Speed: \(Int(speed))km/h)")
                turnController.triggerNavigationTurn(isLeft: true, distanceToJunction: 0)
            }
            else {
                alertBannerText = "🚗 Đang chạy thẳng (\(Int(speed)) km/h) - Nhạy bẻ lái: \(Int(settings.turnSensitivityDegrees))°"
            }
        }
        // 4. KHI ĐANG BẬT XI NHAN (XE ĐANG TRONG KHÚC RẼ):
        else {
            let totalTurned = abs(normalizeAngle(course - turnStartHeading))
            let courseJitter = abs(normalizeAngle(course - lastRecordedCourse))
            let elapsedSinceTurn = now.timeIntervalSince(turnStartTime)
            
            // Đợi qua ít nhất 6 giây để xe đi hết giao lộ mới xét tự tắt khi chạy thẳng (hoặc hết 180s delay tự tắt)
            if elapsedSinceTurn >= 6.0 && totalTurned >= 38.0 && courseJitter < 5.0 {
                turnCompletionSteadyCount += 1
                if turnCompletionSteadyCount >= 4 {
                    print("<<< XE ĐÃ HOÀN THÀNH RẼ VÀ ĐI THẲNG -> TỰ TẮT XI NHAN")
                    turnController.turnOff()
                    courseHistory.removeAll()
                    baselineHeading = course
                    detectedTurnState = .off
                    alertBannerText = "✅ ĐÃ QUA NGÃ RẼ - SẴN SÀNG LƯỢT MỚI"
                    turnCompletionSteadyCount = 0
                }
            } else {
                turnCompletionSteadyCount = 0
            }
        }
        
        lastRecordedCourse = course
    }
    
    /// Tính trung bình góc vòng tròn 360° chính xác
    private func circularMean(angles: [Double]) -> Double {
        guard !angles.isEmpty else { return 0.0 }
        var sinSum: Double = 0
        var cosSum: Double = 0
        for a in angles {
            let rad = a * .pi / 180.0
            sinSum += sin(rad)
            cosSum += cos(rad)
        }
        var avg = atan2(sinSum, cosSum) * 180.0 / .pi
        if avg < 0 { avg += 360.0 }
        return avg
    }
    
    // MARK: - Thuật toán theo Lộ trình có sẵn (Khi người dùng chọn Tuyến đường)
    
    private func processRouteManeuvers(location: CLLocation) {
        guard var route = activeRoute else { return }
        
        guard let maneuverIndex = route.maneuvers.firstIndex(where: { !$0.isCompleted }) else {
            stopNavigation()
            return
        }
        
        var maneuver = route.maneuvers[maneuverIndex]
        self.currentManeuver = maneuver
        
        let maneuverLoc = CLLocation(latitude: maneuver.point.latitude, longitude: maneuver.point.longitude)
        let distance = location.distance(from: maneuverLoc)
        self.distanceToNextManeuver = distance
        
        let bearingToJunction = calculateBearing(from: location.coordinate, to: maneuverLoc.coordinate)
        let vehicleCourse = locationManager.currentCourse
        let speedKmh = locationManager.currentSpeedKmh
        let angleDiff = abs(normalizeAngle(vehicleCourse - bearingToJunction))
        
        let isWithinTriggerDistance = distance <= settings.triggerDistanceMeters && distance >= 8.0
        let isSpeedValid = speedKmh >= settings.minSpeedKmh
        let isTurnAngleSignificant = abs(maneuver.turnAngleDegrees) >= settings.turnSensitivityDegrees
        let isHeadingTowardJunction = angleDiff <= 55.0
        
        if !maneuver.isTriggered && isWithinTriggerDistance && isSpeedValid && isTurnAngleSignificant && isHeadingTowardJunction {
            maneuver.isTriggered = true
            route.maneuvers[maneuverIndex] = maneuver
            self.activeRoute = route
            
            let isLeft = maneuver.type.isTurnLeft
            turnController.triggerNavigationTurn(isLeft: isLeft, distanceToJunction: distance)
            alertBannerText = isLeft ? "🚨 CHUẨN BỊ RẼ TRÁI - XI NHAN BẬT" : "🚨 CHUẨN BỊ RẼ PHẢI - XI NHAN BẬT"
        }
        
        if maneuver.isTriggered && (distance <= 12.0 || (distance < 25.0 && angleDiff > 90.0)) {
            maneuver.isCompleted = true
            route.maneuvers[maneuverIndex] = maneuver
            self.activeRoute = route
            turnController.turnOff()
            alertBannerText = "✅ ĐÃ QUA GIAO LỘ - XI NHAN TẮT"
            
            if maneuverIndex + 1 < route.maneuvers.count {
                self.currentManeuver = route.maneuvers[maneuverIndex + 1]
            }
        }
    }
    
    // MARK: - Public Route Controls
    
    public func startNavigation(route: NavigationRoute) {
        var mutableRoute = route
        for i in 0..<mutableRoute.maneuvers.count {
            mutableRoute.maneuvers[i].isTriggered = false
            mutableRoute.maneuvers[i].isCompleted = false
        }
        self.activeRoute = mutableRoute
        self.isNavigating = true
        self.currentManeuver = mutableRoute.maneuvers.first
        self.remainingTripDistance = mutableRoute.totalDistanceMeters
        locationManager.startTracking()
    }
    
    public func stopNavigation() {
        isNavigating = false
        activeRoute = nil
        currentManeuver = nil
        distanceToNextManeuver = 0
        remainingTripDistance = 0
        stopSimulation()
        turnController.turnOff()
        startFreeRideProtection()
    }
    
    // MARK: - Mathematical Geodesic Helpers
    
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
    
    private func normalizeAngle(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 360.0)
        if a > 180.0 { a -= 360.0 }
        if a < -180.0 { a += 360.0 }
        return a
    }
    
    private func normalize360(_ angle: Double) -> Double {
        return (angle.truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
    }
    
    // MARK: - Simulation Mode
    
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
                speed: 35.0 / 3.6,
                timestamp: Date()
            )
            self.locationManager.locationManager(CLLocationManager(), didUpdateLocations: [mockLoc])
            self.simulationIndex += 1
        }
    }
    
    public func stopSimulation() {
        simulationTimer?.invalidate()
        simulationTimer = nil
        simulationActive = false
    }
}
