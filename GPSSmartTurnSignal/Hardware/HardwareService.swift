import Foundation
import Combine

/// Tầng điều phối phần cứng thống nhất (Facade) hỗ trợ cả BLE và Wi-Fi
public final class HardwareService: ObservableObject {
    public static let shared = HardwareService()
    
    @Published public var connectionStatus: ConnectionStatus = .disconnected
    @Published public var currentMode: HardwareConnectionMode = .bluetooth
    @Published public var statusDetail: String = "Sẵn sàng"
    
    private let bleManager = BLEManager.shared
    private let wifiManager = WiFiManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        self.currentMode = AppSettings.shared.connectionMode
        bindEvents()
        configureActiveMode()
    }
    
    private func bindEvents() {
        // Lắng nghe thay đổi trạng thái từ BLE
        bleManager.$connectionStatus
            .sink { [weak self] status in
                guard let self = self, self.currentMode == .bluetooth else { return }
                self.connectionStatus = status
                if status == .connected {
                    self.statusDetail = "BLE: \(self.bleManager.connectedPeripheral?.name ?? "ESP32") (RSSI: \(self.bleManager.rssi) dBm)"
                } else {
                    self.statusDetail = "BLE: \(status.rawValue)"
                }
            }
            .store(in: &cancellables)
            
        // Lắng nghe thay đổi trạng thái từ Wi-Fi
        wifiManager.$connectionStatus
            .sink { [weak self] status in
                guard let self = self, self.currentMode == .wifi else { return }
                self.connectionStatus = status
                if status == .connected {
                    self.statusDetail = "Wi-Fi: \(AppSettings.shared.wifiHost) (\(self.wifiManager.lastPingMs)ms)"
                } else {
                    self.statusDetail = "Wi-Fi: \(status.rawValue)"
                }
            }
            .store(in: &cancellables)
            
        // Lắng nghe người dùng chuyển đổi chế độ trong cài đặt
        AppSettings.shared.$connectionMode
            .sink { [weak self] newMode in
                guard let self = self else { return }
                self.currentMode = newMode
                self.configureActiveMode()
            }
            .store(in: &cancellables)
    }
    
    /// Khởi động dịch vụ theo chế độ hiện tại
    public func configureActiveMode() {
        switch currentMode {
        case .bluetooth:
            wifiManager.stopMonitoring()
            bleManager.startScanning()
            connectionStatus = bleManager.connectionStatus
        case .wifi:
            bleManager.stopScanning()
            wifiManager.startMonitoring()
            connectionStatus = wifiManager.connectionStatus
        }
    }
    
    /// Gửi lệnh điều khiển xi nhan qua kênh đang kích hoạt
    public func sendCommand(_ command: TurnCommand, completion: ((Bool) -> Void)? = nil) {
        switch currentMode {
        case .bluetooth:
            bleManager.sendCommand(command, completion: completion)
        case .wifi:
            wifiManager.sendCommand(command, completion: completion)
        }
    }
    
    /// Dừng khẩn cấp toàn bộ relay
    public func emergencyStop(completion: ((Bool) -> Void)? = nil) {
        sendCommand(.turnOff, completion: completion)
    }
    
    /// Gửi cấu hình thời gian bật xi nhan
    public func syncDurationConfig(seconds: Int) {
        bleManager.sendConfigDuration(seconds: seconds)
        wifiManager.sendConfigDuration(seconds: seconds)
    }
}
