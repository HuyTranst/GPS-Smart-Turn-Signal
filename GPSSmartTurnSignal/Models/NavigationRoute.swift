import Foundation
import CoreLocation

/// Loại điều hướng tại ngã rẽ
public enum ManeuverType: String, Codable {
    case straight = "Đi thẳng"
    case turnLeft = "Rẽ trái"
    case turnRight = "Rẽ phải"
    case slightLeft = "Chếch sang trái"
    case slightRight = "Chếch sang phải"
    case sharpLeft = "Rẽ gắt bên trái"
    case sharpRight = "Rẽ gắt bên phải"
    case uTurn = "Quay đầu xe"
    case roundabout = "Vào bùng binh"
    case arrive = "Đến đích"
    
    public var isTurnLeft: Bool {
        switch self {
        case .turnLeft, .slightLeft, .sharpLeft:
            return true
        default:
            return false
        }
    }
    
    public var isTurnRight: Bool {
        switch self {
        case .turnRight, .slightRight, .sharpRight:
            return true
        default:
            return false
        }
    }
    
    public var iconName: String {
        switch self {
        case .straight: return "arrow.up"
        case .turnLeft: return "arrow.turn.up.left"
        case .turnRight: return "arrow.turn.up.right"
        case .slightLeft: return "arrow.up.left"
        case .slightRight: return "arrow.up.right"
        case .sharpLeft: return "arrow.turn.left.up"
        case .sharpRight: return "arrow.turn.right.up"
        case .uTurn: return "arrow.uturn.down"
        case .roundabout: return "arrow.triangle.2.circlepath"
        case .arrive: return "mappin.and.ellipse"
        }
    }
}

/// Tọa độ phụ trợ Codable
public struct CoordinatePoint: Codable, Equatable {
    public let latitude: Double
    public let longitude: Double
    
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
    
    public var clLocationCoordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    public var clLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

/// Một thao tác điều hướng tại nút giao lộ
public struct RouteManeuver: Identifiable, Codable {
    public let id: UUID
    public let point: CoordinatePoint
    public let type: ManeuverType
    public let turnAngleDegrees: Double // Góc lệch: âm là trái, dương là phải
    public let instruction: String
    public var distanceMetersFromStart: Double
    public var isTriggered: Bool
    public var isCompleted: Bool
    
    public init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        type: ManeuverType,
        turnAngleDegrees: Double,
        instruction: String,
        distanceMetersFromStart: Double = 0,
        isTriggered: Bool = false,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.point = CoordinatePoint(latitude: latitude, longitude: longitude)
        self.type = type
        self.turnAngleDegrees = turnAngleDegrees
        self.instruction = instruction
        self.distanceMetersFromStart = distanceMetersFromStart
        self.isTriggered = isTriggered
        self.isCompleted = isCompleted
    }
}

/// Toàn bộ thông tin một tuyến đường dẫn đường
public struct NavigationRoute: Identifiable, Codable {
    public let id: UUID
    public let title: String
    public let points: [CoordinatePoint]
    public var maneuvers: [RouteManeuver]
    public let totalDistanceMeters: Double
    public let estimatedDurationSeconds: TimeInterval
    
    public init(
        id: UUID = UUID(),
        title: String,
        points: [CoordinatePoint],
        maneuvers: [RouteManeuver],
        totalDistanceMeters: Double,
        estimatedDurationSeconds: TimeInterval
    ) {
        self.id = id
        self.title = title
        self.points = points
        self.maneuvers = maneuvers
        self.totalDistanceMeters = totalDistanceMeters
        self.estimatedDurationSeconds = estimatedDurationSeconds
    }
    
    /// Tuyến đường mẫu tại Hà Nội phục vụ kiểm thử Offline
    public static var sampleHanoiRoute: NavigationRoute {
        let pts = [
            CoordinatePoint(latitude: 21.028511, longitude: 105.854444), // Hồ Hoàn Kiếm
            CoordinatePoint(latitude: 21.029800, longitude: 105.852200), // Phố Tràng Thi
            CoordinatePoint(latitude: 21.031500, longitude: 105.847500), // Ngã tư Điện Biên Phủ
            CoordinatePoint(latitude: 21.035500, longitude: 105.841200), // Đường Trần Phú
            CoordinatePoint(latitude: 21.037800, longitude: 105.834500), // Lăng Chủ tịch Hồ Chí Minh
        ]
        
        let maneuvers = [
            RouteManeuver(latitude: 21.029800, longitude: 105.852200, type: .turnRight, turnAngleDegrees: 65, instruction: "Rẽ phải vào Tràng Thi"),
            RouteManeuver(latitude: 21.031500, longitude: 105.847500, type: .turnLeft, turnAngleDegrees: -75, instruction: "Rẽ trái vào Điện Biên Phủ"),
            RouteManeuver(latitude: 21.035500, longitude: 105.841200, type: .turnRight, turnAngleDegrees: 70, instruction: "Rẽ phải vào Trần Phú"),
            RouteManeuver(latitude: 21.037800, longitude: 105.834500, type: .arrive, turnAngleDegrees: 0, instruction: "Đã đến Lăng Bác")
        ]
        
        return NavigationRoute(
            title: "Hà Nội: Hồ Gươm -> Lăng Bác (Test)",
            points: pts,
            maneuvers: maneuvers,
            totalDistanceMeters: 2800,
            estimatedDurationSeconds: 480
        )
    }
    
    /// Tuyến đường mẫu tại TP. Hồ Chí Minh phục vụ kiểm thử Offline
    public static var sampleHcmcRoute: NavigationRoute {
        let pts = [
            CoordinatePoint(latitude: 10.776889, longitude: 106.700806), // Chợ Bến Thành
            CoordinatePoint(latitude: 10.773500, longitude: 106.698000), // Lê Lai
            CoordinatePoint(latitude: 10.771200, longitude: 106.693500), // Nguyễn Thị Nghĩa
            CoordinatePoint(latitude: 10.768900, longitude: 106.690200), // Cách Mạng Tháng 8
            CoordinatePoint(latitude: 10.771500, longitude: 106.685500), // Nguyễn Thị Minh Khai
        ]
        
        let maneuvers = [
            RouteManeuver(latitude: 10.773500, longitude: 106.698000, type: .turnRight, turnAngleDegrees: 72, instruction: "Rẽ phải vào Lê Lai"),
            RouteManeuver(latitude: 10.771200, longitude: 106.693500, type: .turnLeft, turnAngleDegrees: -68, instruction: "Rẽ trái vào Nguyễn Thị Nghĩa"),
            RouteManeuver(latitude: 10.768900, longitude: 106.690200, type: .turnRight, turnAngleDegrees: 80, instruction: "Rẽ phải vào CMT8"),
            RouteManeuver(latitude: 10.771500, longitude: 106.685500, type: .arrive, turnAngleDegrees: 0, instruction: "Đến điểm dừng chân")
        ]
        
        return NavigationRoute(
            title: "TP.HCM: Bến Thành -> CMT8 (Test)",
            points: pts,
            maneuvers: maneuvers,
            totalDistanceMeters: 3100,
            estimatedDurationSeconds: 540
        )
    }
}
