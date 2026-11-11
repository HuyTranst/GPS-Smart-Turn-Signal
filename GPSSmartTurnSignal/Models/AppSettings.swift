import Foundation
import Combine

/// Quản lý toàn bộ cấu hình ứng dụng và lưu trữ lâu dài vào UserDefaults
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()
    
    // MARK: - Keys
    private enum Keys {
        static let isAutoSignalEnabled = "gps_signal_isAutoSignalEnabled"
        static let connectionMode = "gps_signal_connectionMode"
        static let wifiHost = "gps_signal_wifiHost"
        static let wifiPort = "gps_signal_wifiPort"
        static let bleDeviceName = "gps_signal_bleDeviceName"
        static let savedPeripheralUUID = "gps_signal_savedPeripheralUUID"
        static let turnDurationSeconds = "gps_signal_turnDurationSeconds"
        static let triggerDistanceMeters = "gps_signal_triggerDistanceMeters"
        static let turnSensitivityDegrees = "gps_signal_turnSensitivityDegrees"
        static let minSpeedKmh = "gps_signal_minSpeedKmh"
        static let cooldownSeconds = "gps_signal_cooldownSeconds"
        static let isSoundAlertEnabled = "gps_signal_isSoundAlertEnabled"
        static let isHapticFeedbackEnabled = "gps_signal_isHapticFeedbackEnabled"
    }
    
    // MARK: - Published Properties
    
    /// Bật / Tắt chế độ xi nhan tự động khi dẫn đường
    @Published public var isAutoSignalEnabled: Bool {
        didSet { UserDefaults.standard.set(isAutoSignalEnabled, forKey: Keys.isAutoSignalEnabled) }
    }
    
    /// Chế độ kết nối: BLE hoặc Wi-Fi
    @Published public var connectionMode: HardwareConnectionMode {
        didSet { UserDefaults.standard.set(connectionMode.rawValue, forKey: Keys.connectionMode) }
    }
    
    /// Địa chỉ IP của ESP32 (Mặc định 192.168.4.1 ở chế độ AP)
    @Published public var wifiHost: String {
        didSet { UserDefaults.standard.set(wifiHost, forKey: Keys.wifiHost) }
    }
    
    /// Cổng kết nối HTTP của ESP32 (Mặc định 80)
    @Published public var wifiPort: Int {
        didSet { UserDefaults.standard.set(wifiPort, forKey: Keys.wifiPort) }
    }
    
    /// Tên thiết bị BLE cần ghép nối (Mặc định: GPS_Turn_Signal)
    @Published public var bleDeviceName: String {
        didSet { UserDefaults.standard.set(bleDeviceName, forKey: Keys.bleDeviceName) }
    }
    
    /// UUID thiết bị BLE đã ghép nối trước đó
    @Published public var savedPeripheralUUID: String? {
        didSet { UserDefaults.standard.set(savedPeripheralUUID, forKey: Keys.savedPeripheralUUID) }
    }
    
    /// Thời gian bật xi nhan trước khi tự tắt (Mặc định 50 giây)
    @Published public var turnDurationSeconds: Double {
        didSet { UserDefaults.standard.set(turnDurationSeconds, forKey: Keys.turnDurationSeconds) }
    }
    
    /// Khoảng cách trước giao lộ để kích hoạt xi nhan (Mặc định 80m, dải 30m - 200m)
    @Published public var triggerDistanceMeters: Double {
        didSet { UserDefaults.standard.set(triggerDistanceMeters, forKey: Keys.triggerDistanceMeters) }
    }
    
    /// Độ nhạy nhận diện góc rẽ tối thiểu (Mặc định 45 độ, dải 30 - 70 độ)
    @Published public var turnSensitivityDegrees: Double {
        didSet { UserDefaults.standard.set(turnSensitivityDegrees, forKey: Keys.turnSensitivityDegrees) }
    }
    
    /// Tốc độ GPS tối thiểu để kích hoạt (Mặc định 10 km/h, tránh kích hoạt khi đi bộ/dừng đèn đỏ)
    @Published public var minSpeedKmh: Double {
        didSet { UserDefaults.standard.set(minSpeedKmh, forKey: Keys.minSpeedKmh) }
    }
    
    /// Thời gian chờ giữa 2 lần kích hoạt liên tiếp (tránh lặp lệnh, mặc định 25 giây)
    @Published public var cooldownSeconds: Double {
        didSet { UserDefaults.standard.set(cooldownSeconds, forKey: Keys.cooldownSeconds) }
    }
    
    /// Bật/Tắt âm thanh cảnh báo khi kích hoạt xi nhan
    @Published public var isSoundAlertEnabled: Bool {
        didSet { UserDefaults.standard.set(isSoundAlertEnabled, forKey: Keys.isSoundAlertEnabled) }
    }
    
    /// Bật/Tắt rung phản hồi khi kích hoạt
    @Published public var isHapticFeedbackEnabled: Bool {
        didSet { UserDefaults.standard.set(isHapticFeedbackEnabled, forKey: Keys.isHapticFeedbackEnabled) }
    }
    
    // MARK: - Init
    private init() {
        let defaults = UserDefaults.standard
        
        self.isAutoSignalEnabled = defaults.object(forKey: Keys.isAutoSignalEnabled) != nil ?
            defaults.bool(forKey: Keys.isAutoSignalEnabled) : true
            
        if let modeRaw = defaults.string(forKey: Keys.connectionMode),
           let mode = HardwareConnectionMode(rawValue: modeRaw) {
            self.connectionMode = mode
        } else {
            self.connectionMode = .bluetooth
        }
        
        self.wifiHost = defaults.string(forKey: Keys.wifiHost) ?? "192.168.4.1"
        self.wifiPort = defaults.object(forKey: Keys.wifiPort) != nil ?
            defaults.integer(forKey: Keys.wifiPort) : 80
            
        self.bleDeviceName = defaults.string(forKey: Keys.bleDeviceName) ?? "GPS_Turn_Signal"
        self.savedPeripheralUUID = defaults.string(forKey: Keys.savedPeripheralUUID)
        
        self.turnDurationSeconds = defaults.object(forKey: Keys.turnDurationSeconds) != nil ?
            defaults.double(forKey: Keys.turnDurationSeconds) : 50.0
            
        self.triggerDistanceMeters = defaults.object(forKey: Keys.triggerDistanceMeters) != nil ?
            defaults.double(forKey: Keys.triggerDistanceMeters) : 80.0
            
        self.turnSensitivityDegrees = defaults.object(forKey: Keys.turnSensitivityDegrees) != nil ?
            defaults.double(forKey: Keys.turnSensitivityDegrees) : 45.0
            
        self.minSpeedKmh = defaults.object(forKey: Keys.minSpeedKmh) != nil ?
            defaults.double(forKey: Keys.minSpeedKmh) : 10.0
            
        self.cooldownSeconds = defaults.object(forKey: Keys.cooldownSeconds) != nil ?
            defaults.double(forKey: Keys.cooldownSeconds) : 25.0
            
        self.isSoundAlertEnabled = defaults.object(forKey: Keys.isSoundAlertEnabled) != nil ?
            defaults.bool(forKey: Keys.isSoundAlertEnabled) : true
            
        self.isHapticFeedbackEnabled = defaults.object(forKey: Keys.isHapticFeedbackEnabled) != nil ?
            defaults.bool(forKey: Keys.isHapticFeedbackEnabled) : true
    }
    
    /// Đặt lại toàn bộ cấu hình về mặc định
    public func resetToDefaults() {
        isAutoSignalEnabled = true
        connectionMode = .bluetooth
        wifiHost = "192.168.4.1"
        wifiPort = 80
        bleDeviceName = "GPS_Turn_Signal"
        turnDurationSeconds = 50.0
        triggerDistanceMeters = 80.0
        turnSensitivityDegrees = 45.0
        minSpeedKmh = 10.0
        cooldownSeconds = 25.0
        isSoundAlertEnabled = true
        isHapticFeedbackEnabled = true
    }
}
