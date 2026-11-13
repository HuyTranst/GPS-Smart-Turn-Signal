import Foundation
import Combine

/// Quản lý toàn bộ cấu hình ứng dụng và lưu trữ bền vững vào UserDefaults (luôn nhớ cho các lần mở sau)
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
        static let isCameraWarningEnabled = "gps_signal_isCameraWarningEnabled"
        static let cameraWarningDistanceMeters = "gps_signal_cameraWarningDistanceMeters"
        static let isCameraRepeatingVibrationEnabled = "gps_signal_isCameraRepeatingVibrationEnabled"
        static let cameraVibrationPulses = "gps_signal_cameraVibrationPulses"
        static let cameraVibrationPauseSeconds = "gps_signal_cameraVibrationPauseSeconds"
        static let hasAppliedV108Migration = "gps_signal_migrated_v108"
    }
    
    // MARK: - Published Properties
    
    /// Bật / Tắt chế độ xi nhan tự động
    @Published public var isAutoSignalEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoSignalEnabled, forKey: Keys.isAutoSignalEnabled)
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Chế độ kết nối: BLE hoặc Wi-Fi
    @Published public var connectionMode: HardwareConnectionMode {
        didSet {
            UserDefaults.standard.set(connectionMode.rawValue, forKey: Keys.connectionMode)
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Địa chỉ IP của ESP32 (Mặc định 192.168.4.1 ở chế độ AP)
    @Published public var wifiHost: String {
        didSet {
            UserDefaults.standard.set(wifiHost, forKey: Keys.wifiHost)
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Cổng kết nối HTTP của ESP32 (Mặc định 80)
    @Published public var wifiPort: Int {
        didSet {
            UserDefaults.standard.set(wifiPort, forKey: Keys.wifiPort)
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Tên thiết bị BLE cần ghép nối (Mặc định: GPS_Turn_Signal)
    @Published public var bleDeviceName: String {
        didSet {
            UserDefaults.standard.set(bleDeviceName, forKey: Keys.bleDeviceName)
            UserDefaults.standard.synchronize()
        }
    }
    
    /// UUID thiết bị BLE đã ghép nối trước đó
    @Published public var savedPeripheralUUID: String? {
        didSet {
            UserDefaults.standard.set(savedPeripheralUUID, forKey: Keys.savedPeripheralUUID)
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Thời gian giữ xi nhan / Delay tự tắt (Mặc định 180 giây, dải 10s - 300s)
    @Published public var turnDurationSeconds: Double {
        didSet {
            UserDefaults.standard.set(turnDurationSeconds, forKey: Keys.turnDurationSeconds)
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Khoảng cách trước giao lộ khi dẫn đường theo tuyến (Mặc định 80m, dải 30m - 200m)
    @Published public var triggerDistanceMeters: Double {
        didSet {
            UserDefaults.standard.set(triggerDistanceMeters, forKey: Keys.triggerDistanceMeters)
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Độ nhạy nhận diện góc bẻ lái vào cua (Mặc định 14 độ để vừa quẹo là bật liền)
    @Published public var turnSensitivityDegrees: Double {
        didSet {
            UserDefaults.standard.set(turnSensitivityDegrees, forKey: Keys.turnSensitivityDegrees)
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Tốc độ GPS tối thiểu để kích hoạt (Mặc định 3 km/h - vào cua chậm vẫn nhận diện ngay)
    @Published public var minSpeedKmh: Double {
        didSet {
            UserDefaults.standard.set(minSpeedKmh, forKey: Keys.minSpeedKmh)
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Thời gian chờ giữa 2 lần kích hoạt liên tiếp (Mặc định 3 giây để qua ngã tư kế tiếp vẫn bật liền)
    @Published public var cooldownSeconds: Double {
        didSet {
            UserDefaults.standard.set(cooldownSeconds, forKey: Keys.cooldownSeconds)
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Bật/Tắt cảnh báo Camera giao thông & Đèn số 3 ESP32
    @Published public var isCameraWarningEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isCameraWarningEnabled, forKey: Keys.isCameraWarningEnabled)
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Khoảng cách cảnh báo Camera giao thông (Mặc định 150 mét, dải 50m - 1000m)
    @Published public var cameraWarningDistanceMeters: Double {
        didSet {
            UserDefaults.standard.set(cameraWarningDistanceMeters, forKey: Keys.cameraWarningDistanceMeters)
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Bật/Tắt âm thanh cảnh báo khi kích hoạt xi nhan & camera
    @Published public var isSoundAlertEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSoundAlertEnabled, forKey: Keys.isSoundAlertEnabled)
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Bật/Tắt rung phản hồi khi kích hoạt
    @Published public var isHapticFeedbackEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isHapticFeedbackEnabled, forKey: Keys.isHapticFeedbackEnabled)
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Bật/Tắt chế độ rung chu kỳ cảnh báo Camera (Rung 5 lần, nghỉ 3 giây cho đến khi ra khỏi vùng)
    @Published public var isCameraRepeatingVibrationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isCameraRepeatingVibrationEnabled, forKey: Keys.isCameraRepeatingVibrationEnabled)
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Số lần rung trong mỗi đợt cảnh báo camera (Mặc định 5 lần, dải 1 - 10)
    @Published public var cameraVibrationPulses: Int {
        didSet {
            UserDefaults.standard.set(cameraVibrationPulses, forKey: Keys.cameraVibrationPulses)
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Thời gian tạm nghỉ giữa các đợt rung camera (Mặc định 3.0 giây, dải 1s - 8s)
    @Published public var cameraVibrationPauseSeconds: Double {
        didSet {
            UserDefaults.standard.set(cameraVibrationPauseSeconds, forKey: Keys.cameraVibrationPauseSeconds)
            UserDefaults.standard.synchronize()
        }
    }
    
    // MARK: - Init
    private init() {
        let defaults = UserDefaults.standard
        
        // Áp dụng bộ thông số tối ưu mới cho bản v1.0.8 một lần duy nhất (nếu nâng cấp từ bản cũ)
        if !defaults.bool(forKey: Keys.hasAppliedV108Migration) {
            defaults.set(180.0, forKey: Keys.turnDurationSeconds)
            defaults.set(150.0, forKey: Keys.cameraWarningDistanceMeters)
            defaults.set(14.0, forKey: Keys.turnSensitivityDegrees)
            defaults.set(3.0, forKey: Keys.minSpeedKmh)
            defaults.set(3.0, forKey: Keys.cooldownSeconds)
            defaults.set(true, forKey: Keys.isCameraWarningEnabled)
            defaults.set(true, forKey: Keys.hasAppliedV108Migration)
            defaults.synchronize()
        }
        
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
            defaults.double(forKey: Keys.turnDurationSeconds) : 180.0
            
        self.triggerDistanceMeters = defaults.object(forKey: Keys.triggerDistanceMeters) != nil ?
            defaults.double(forKey: Keys.triggerDistanceMeters) : 80.0
            
        self.turnSensitivityDegrees = defaults.object(forKey: Keys.turnSensitivityDegrees) != nil ?
            defaults.double(forKey: Keys.turnSensitivityDegrees) : 14.0
            
        self.minSpeedKmh = defaults.object(forKey: Keys.minSpeedKmh) != nil ?
            defaults.double(forKey: Keys.minSpeedKmh) : 3.0
            
        self.cooldownSeconds = defaults.object(forKey: Keys.cooldownSeconds) != nil ?
            defaults.double(forKey: Keys.cooldownSeconds) : 3.0
            
        self.isCameraWarningEnabled = defaults.object(forKey: Keys.isCameraWarningEnabled) != nil ?
            defaults.bool(forKey: Keys.isCameraWarningEnabled) : true
            
        self.cameraWarningDistanceMeters = defaults.object(forKey: Keys.cameraWarningDistanceMeters) != nil ?
            defaults.double(forKey: Keys.cameraWarningDistanceMeters) : 150.0
            
        self.isSoundAlertEnabled = defaults.object(forKey: Keys.isSoundAlertEnabled) != nil ?
            defaults.bool(forKey: Keys.isSoundAlertEnabled) : true
            
        self.isHapticFeedbackEnabled = defaults.object(forKey: Keys.isHapticFeedbackEnabled) != nil ?
            defaults.bool(forKey: Keys.isHapticFeedbackEnabled) : true
            
        self.isCameraRepeatingVibrationEnabled = defaults.object(forKey: Keys.isCameraRepeatingVibrationEnabled) != nil ?
            defaults.bool(forKey: Keys.isCameraRepeatingVibrationEnabled) : true
            
        self.cameraVibrationPulses = defaults.object(forKey: Keys.cameraVibrationPulses) != nil ?
            defaults.integer(forKey: Keys.cameraVibrationPulses) : 5
            
        self.cameraVibrationPauseSeconds = defaults.object(forKey: Keys.cameraVibrationPauseSeconds) != nil ?
            defaults.double(forKey: Keys.cameraVibrationPauseSeconds) : 3.0
    }
    
    /// Đặt lại toàn bộ cấu hình về mặc định chuẩn
    public func resetToDefaults() {
        isAutoSignalEnabled = true
        connectionMode = .bluetooth
        wifiHost = "192.168.4.1"
        wifiPort = 80
        bleDeviceName = "GPS_Turn_Signal"
        turnDurationSeconds = 180.0
        triggerDistanceMeters = 80.0
        turnSensitivityDegrees = 14.0
        minSpeedKmh = 3.0
        cooldownSeconds = 3.0
        isCameraWarningEnabled = true
        cameraWarningDistanceMeters = 150.0
        isSoundAlertEnabled = true
        isHapticFeedbackEnabled = true
        isCameraRepeatingVibrationEnabled = true
        cameraVibrationPulses = 5
        cameraVibrationPauseSeconds = 3.0
    }
}
