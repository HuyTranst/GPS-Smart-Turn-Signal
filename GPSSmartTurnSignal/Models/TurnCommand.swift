import Foundation

/// Lệnh điều khiển xi nhan và đèn báo gửi tới ESP32
public enum TurnCommand: String, Codable {
    case turnLeft = "TURN_LEFT"
    case turnRight = "TURN_RIGHT"
    case turnOff = "TURN_OFF"
    case cameraWarningOn = "CAMERA_ON"
    case cameraWarningOff = "CAMERA_OFF"
    
    /// Chuỗi payload văn bản gửi qua BLE / HTTP
    public var payloadString: String {
        return self.rawValue
    }
}

/// Trạng thái xi nhan hiện tại
public enum TurnSignalState: String, Codable {
    case off = "OFF"
    case left = "LEFT"
    case right = "RIGHT"
    
    public var displayName: String {
        switch self {
        case .off: return "Đang tắt"
        case .left: return "Xi nhan TRÁI"
        case .right: return "Xi nhan PHẢI"
        }
    }
}

/// Chế độ kết nối giữa iPhone và ESP32
public enum HardwareConnectionMode: String, CaseIterable, Identifiable, Codable {
    case bluetooth = "Bluetooth (BLE)"
    case wifi = "Wi-Fi nội bộ"
    
    public var id: String { rawValue }
}

/// Trạng thái kết nối phần cứng
public enum ConnectionStatus: String {
    case disconnected = "Chưa kết nối"
    case scanning = "Đang tìm thiết bị..."
    case connecting = "Đang kết nối..."
    case connected = "Đã kết nối"
    case failed = "Kết nối thất bại"
}
