import Foundation
import CoreLocation
import Combine
import AVFoundation
import UIKit

/// Quản lý phát hiện và cảnh báo Camera giao thông (500m) & Ghi nhớ vị trí thủ công
public final class TrafficCameraManager: ObservableObject {
    public static let shared = TrafficCameraManager()
    
    // Danh sách Camera
    @Published public var localCameras: [TrafficCamera] = []
    @Published public var osmCameras: [TrafficCamera] = []
    @Published public var allCameras: [TrafficCamera] = []
    
    // Trạng thái cảnh báo thời gian thực
    @Published public var isCameraWarningActive: Bool = false
    @Published public var warningDistanceMeters: Int = 0
    @Published public var activeWarningCamera: TrafficCamera? = nil
    @Published public var lastActionMessage: String? = nil
    
    // Cự ly kích hoạt cảnh báo mặc định là 500 mét
    public let warningThresholdMeters: Double = 500.0
    
    private var activeWarningCameraId: String? = nil
    private var lastSpokenTime: Date = Date.distantPast
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var cancellables = Set<AnyCancellable>()
    
    // Đường dẫn file lưu trữ Local và Offline Cache
    private var localCamerasFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("traffic_cameras_local.json")
    }
    
    private var osmCacheFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("traffic_cameras_osm_cache.json")
    }
    
    private init() {
        loadSavedCameras()
        loadOsmCache()
        rebuildAllCamerasList()
        setupLocationTracking()
    }
    
    // MARK: - Khởi tạo theo dõi vị trí GPS
    
    private func setupLocationTracking() {
        LocationManager.shared.$currentLocation
            .compactMap { $0 }
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] location in
                self?.evaluateCameraProximity(currentLocation: location)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Quản lý Camera Local (Ghi nhớ thủ công)
    
    /// Người dùng bấm nút "Ghi nhớ Camera giao thông" tại vị trí hiện tại
    public func saveCameraAtCurrentLocation(title: String? = nil, speedLimit: Int? = nil) {
        guard let location = LocationManager.shared.currentLocation else {
            notifyMessage("Chưa có tín hiệu GPS để lưu vị trí!")
            return
        }
        
        let customTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? title!
            : "Camera phạt nguội (Ghim lúc \(formattedTime(Date())))"
            
        let newCam = TrafficCamera(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            title: customTitle,
            speedLimitKmh: speedLimit,
            sourceType: .localUser,
            createdAt: Date()
        )
        
        // Thêm vào danh sách Local
        localCameras.insert(newCam, at: 0)
        saveLocalCamerasToDisk()
        rebuildAllCamerasList()
        
        // Phản hồi rung Haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Phát thông báo âm thanh
        speak("Đã ghi nhớ vị trí camera giao thông thành công!")
        notifyMessage("Đã ghim vị trí Camera giao thông tại đây!")
        
        print("Đã lưu camera mới: \(newCam.title) tại (\(newCam.latitude), \(newCam.longitude))")
    }
    
    /// Xóa một camera khỏi danh sách
    public func deleteCamera(id: String) {
        localCameras.removeAll { $0.id == id }
        osmCameras.removeAll { $0.id == id }
        saveLocalCamerasToDisk()
        rebuildAllCamerasList()
        notifyMessage("Đã xóa camera giao thông")
    }
    
    // MARK: - Thuật toán Đánh giá Cự ly & Phát Cảnh Báo 500m
    
    private func evaluateCameraProximity(currentLocation: CLLocation) {
        guard !allCameras.isEmpty else { return }
        
        // Tìm camera gần vị trí xe nhất
        var nearestCam: TrafficCamera? = nil
        var minDistance: Double = Double.infinity
        
        for cam in allCameras {
            let camLoc = CLLocation(latitude: cam.latitude, longitude: cam.longitude)
            let dist = currentLocation.distance(from: camLoc)
            if dist < minDistance {
                minDistance = dist
                nearestCam = cam
            }
        }
        
        guard let nearest = nearestCam else { return }
        
        // KIỂM TRA ĐIỀU KIỆN TRONG VÙNG CẢNH BÁO (<= 500 mét)
        if minDistance <= warningThresholdMeters {
            warningDistanceMeters = Int(minDistance)
            activeWarningCamera = nearest
            
            // Kích hoạt phát cảnh báo lần đầu khi tiến vào vùng 500m
            if activeWarningCameraId != nearest.id {
                activeWarningCameraId = nearest.id
                isCameraWarningActive = true
                
                print("CẢNH BÁO CAMERA GIAO THÔNG! Cự ly: \(Int(minDistance))m -> BẬT ĐÈN SỐ 3 TRÊN ESP32")
                
                // 1. GỬI LỆNH ĐẾN ESP32 ĐỂ MỞ ĐÈN SỐ 3
                HardwareService.shared.sendCommand(.cameraWarningOn)
                
                // 2. PHÁT ÂM THANH CẢNH BÁO TIẾNG VIỆT
                let speedText = nearest.speedLimitKmh != nil ? ", giới hạn \(nearest.speedLimitKmh!) kilomet trên giờ" : ""
                let alertSpeech = "Chú ý, phía trước năm trăm mét có camera giao thông\(speedText), vui lòng chú ý tốc độ!"
                speak(alertSpeech)
                
                // Phản hồi rung cảnh báo
                let feedback = UINotificationFeedbackGenerator()
                feedback.notificationOccurred(.warning)
            }
        } else {
            // Khi xe đã ra khỏi vùng 500 mét (đã vượt qua camera hoặc đi xa hơn 550m)
            if isCameraWarningActive && minDistance > (warningThresholdMeters + 60.0) {
                print("Đã ra khỏi vùng camera -> TẮT ĐÈN SỐ 3 TRÊN ESP32")
                isCameraWarningActive = false
                activeWarningCamera = nil
                warningDistanceMeters = 0
                
                // GỬI LỆNH TẮT ĐÈN SỐ 3
                HardwareService.shared.sendCommand(.cameraWarningOff)
                
                // Cho phép phát hiện lại sau 15 giây
                DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
                    self?.activeWarningCameraId = nil
                }
            }
        }
    }
    
    // MARK: - Phát Giọng Nói Cảnh Báo
    
    private func speak(_ text: String) {
        guard Date().timeIntervalSince(lastSpokenTime) > 3.0 else { return }
        lastSpokenTime = Date()
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "vi-VN") ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.volume = 1.0
        
        speechSynthesizer.speak(utterance)
    }
    
    private func notifyMessage(_ msg: String) {
        self.lastActionMessage = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if self?.lastActionMessage == msg {
                self?.lastActionMessage = nil
            }
        }
    }
    
    // MARK: - Đọc/Ghi Dữ Liệu Bộ Nhớ
    
    private func rebuildAllCamerasList() {
        // Ưu tiên danh sách Local do người dùng tự lưu trước, sau đó là OpenStreetMap
        var combined = localCameras
        for osm in osmCameras {
            if !combined.contains(where: { $0.id == osm.id }) {
                combined.append(osm)
            }
        }
        self.allCameras = combined
    }
    
    private func saveLocalCamerasToDisk() {
        do {
            let data = try JSONEncoder().encode(localCameras)
            try data.write(to: localCamerasFileURL, options: .atomic)
        } catch {
            print("Lỗi lưu file local camera: \(error.localizedDescription)")
        }
    }
    
    private func loadSavedCameras() {
        guard FileManager.default.fileExists(atPath: localCamerasFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: localCamerasFileURL)
            let loaded = try JSONDecoder().decode([TrafficCamera].self, from: data)
            self.localCameras = loaded
        } catch {
            print("Lỗi đọc file local camera: \(error.localizedDescription)")
        }
    }
    
    private func loadOsmCache() {
        guard FileManager.default.fileExists(atPath: osmCacheFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: osmCacheFileURL)
            let loaded = try JSONDecoder().decode([TrafficCamera].self, from: data)
            self.osmCameras = loaded
        } catch {
            print("Lỗi đọc file cache OSM camera: \(error.localizedDescription)")
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm dd/MM"
        return formatter.string(from: date)
    }
}
