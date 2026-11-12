import Foundation
import CoreLocation

/// Nguồn gốc dữ liệu của Camera giao thông
public enum CameraSourceType: String, Codable {
    case localUser = "Đã lưu thủ công (Local)"
    case openStreetMap = "OpenStreetMap"
}

/// Mô hình đại diện cho một vị trí Camera giao thông / Phạt nguội
public struct TrafficCamera: Identifiable, Codable, Equatable {
    public let id: String
    public let latitude: Double
    public let longitude: Double
    public var title: String
    public var speedLimitKmh: Int?
    public let sourceType: CameraSourceType
    public let createdAt: Date
    
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    public init(id: String = UUID().uuidString,
                latitude: Double,
                longitude: Double,
                title: String = "No name",
                speedLimitKmh: Int? = nil,
                sourceType: CameraSourceType = .localUser,
                createdAt: Date = Date()) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.title = title
        self.speedLimitKmh = speedLimitKmh
        self.sourceType = sourceType
        self.createdAt = createdAt
    }
    
    public static func == (lhs: TrafficCamera, rhs: TrafficCamera) -> Bool {
        return lhs.id == rhs.id
            && lhs.latitude == rhs.latitude
            && lhs.longitude == rhs.longitude
            && lhs.title == rhs.title
            && lhs.speedLimitKmh == rhs.speedLimitKmh
            && lhs.sourceType == rhs.sourceType
    }
}
