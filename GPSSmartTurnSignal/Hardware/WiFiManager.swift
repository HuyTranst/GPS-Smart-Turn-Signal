import Foundation
import Combine

/// Quản lý giao tiếp qua Wi-Fi nội bộ bằng giao thức HTTP REST API tới ESP32
public final class WiFiManager: ObservableObject {
    public static let shared = WiFiManager()
    
    @Published public var connectionStatus: ConnectionStatus = .disconnected
    @Published public var lastPingMs: Int = 0
    @Published public var lastStatusPayload: String = ""
    
    private var pingTimer: Timer?
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 2.0 // Timeout ngắn để phản hồi nhanh
        config.timeoutIntervalForResource = 3.0
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }
    
    /// Bắt đầu kiểm tra nhịp tim định kỳ tới ESP32
    public func startMonitoring() {
        stopMonitoring()
        checkConnection()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.checkConnection()
        }
    }
    
    /// Dừng kiểm tra nhịp tim
    public func stopMonitoring() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    /// Kiểm tra kết nối tới ESP32
    public func checkConnection(completion: ((Bool) -> Void)? = nil) {
        let settings = AppSettings.shared
        guard let url = URL(string: "http://\(settings.wifiHost):\(settings.wifiPort)/api/status") else {
            DispatchQueue.main.async { self.connectionStatus = .failed }
            completion?(false)
            return
        }
        
        let start = Date()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        session.dataTask(with: request) { [weak self] data, response, error in
            let duration = Int(Date().timeIntervalSince(start) * 1000)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self.connectionStatus = .connected
                    self.lastPingMs = duration
                    if let d = data, let text = String(data: d, encoding: .utf8) {
                        self.lastStatusPayload = text
                    }
                    completion?(true)
                } else {
                    self.connectionStatus = .disconnected
                    completion?(false)
                }
            }
        }.resume()
    }
    
    /// Gửi lệnh điều khiển xi nhan qua HTTP
    public func sendCommand(_ command: TurnCommand, completion: ((Bool) -> Void)? = nil) {
        let settings = AppSettings.shared
        var dirParam = "off"
        switch command {
        case .turnLeft: dirParam = "left"
        case .turnRight: dirParam = "right"
        case .turnOff: dirParam = "off"
        case .cameraWarningOn: dirParam = "camera_on"
        case .cameraWarningOff: dirParam = "camera_off"
        }
        
        guard let url = URL(string: "http://\(settings.wifiHost):\(settings.wifiPort)/api/turn?direction=\(dirParam)") else {
            completion?(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        session.dataTask(with: request) { [weak self] data, response, error in
            let success = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                if success {
                    self?.connectionStatus = .connected
                    print("Wi-Fi Sent command: \(command.rawValue) -> OK")
                } else {
                    print("Wi-Fi Send command failed: \(error?.localizedDescription ?? "HTTP error")")
                }
                completion?(success)
            }
        }.resume()
    }
    
    /// Gửi cấu hình thời gian bật xi nhan xuống ESP32
    public func sendConfigDuration(seconds: Int) {
        let settings = AppSettings.shared
        guard let url = URL(string: "http://\(settings.wifiHost):\(settings.wifiPort)/api/config?duration=\(seconds)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        session.dataTask(with: request).resume()
    }
}
