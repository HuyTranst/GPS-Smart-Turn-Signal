import Foundation
import CoreLocation
import Combine
import AVFoundation
import UIKit

/// Quản lý phát hiện và cảnh báo Camera giao thông (Mặc định 150m) & Ghi nhớ vị trí thủ công
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
    @Published public var lastPinnedCamera: TrafficCamera? = nil
    @Published public var isInspectingCameraLocation: Bool = false
    
    // Cự ly kích hoạt cảnh báo động theo Cài đặt (Mặc định 150 mét)
    public var warningThresholdMeters: Double {
        return AppSettings.shared.cameraWarningDistanceMeters
    }
    
    private var activeWarningCameraId: String? = nil
    private var lastSpokenTime: Date = Date.distantPast
    private var manuallyEditedCameraIds = Set<String>()
    private var actionMessageWorkItem: DispatchWorkItem?
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
    
    /// Người dùng bấm nút "Ghi nhớ Camera giao thông" tại vị trí hiện tại (hoặc tọa độ truyền vào)
    /// Tự động lấy tên đường / địa chỉ gần đúng; nếu không tìm được sẽ ghi "No name" và cho phép sửa thủ công.
    public func saveCameraAtCurrentLocation(
        title: String? = nil,
        speedLimit: Int? = nil,
        customCoordinate: CLLocationCoordinate2D? = nil
    ) {
        let targetCoordinate: CLLocationCoordinate2D?
        if let customCoordinate = customCoordinate {
            targetCoordinate = customCoordinate
        } else {
            targetCoordinate = LocationManager.shared.currentLocation?.coordinate
        }
        
        guard let coordinate = targetCoordinate else {
            notifyMessage("Chưa có tín hiệu GPS để lưu vị trí!")
            return
        }
        
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasManualTitle = !trimmedTitle.isEmpty
        let initialTitle = hasManualTitle ? trimmedTitle : "No name"
        
        let newCam = TrafficCamera(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            title: initialTitle,
            speedLimitKmh: speedLimit,
            sourceType: .localUser,
            createdAt: Date()
        )
        
        if hasManualTitle {
            manuallyEditedCameraIds.insert(newCam.id)
        }
        
        // Lưu ngay vào danh sách Local để không bị mất tọa độ dù mất mạng hoặc tắt app
        localCameras.insert(newCam, at: 0)
        saveLocalCamerasToDisk()
        rebuildAllCamerasList()
        lastPinnedCamera = newCam
        
        // Phản hồi rung Haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Phát thông báo âm thanh
        speak("Đã ghi nhớ vị trí camera giao thông thành công!")
        
        if hasManualTitle {
            notifyMessage("Đã ghim: \(initialTitle)", duration: 6.0)
        } else {
            notifyMessage("Đã ghim Camera (đang dò tên đường...)", duration: 6.0)
            
            // Tự động phân giải tên đường / địa chỉ gần đúng bất đồng bộ; fallback "No name"
            let camId = newCam.id
            resolveStreetAddress(for: coordinate) { [weak self] resolvedAddress in
                guard let self = self else { return }
                guard !self.manuallyEditedCameraIds.contains(camId) else { return }
                
                if let index = self.localCameras.firstIndex(where: { $0.id == camId }) {
                    self.localCameras[index].title = resolvedAddress
                    self.saveLocalCamerasToDisk()
                    self.rebuildAllCamerasList()
                    if self.lastPinnedCamera?.id == camId {
                        self.lastPinnedCamera = self.localCameras[index]
                    }
                    if self.activeWarningCamera?.id == camId {
                        self.activeWarningCamera = self.localCameras[index]
                    }
                }
                self.notifyMessage("Đã ghim: \(resolvedAddress)", duration: 6.0)
                print("Cập nhật tên đường camera \(camId): \(resolvedAddress)")
            }
        }
        
        print("Đã lưu camera mới: \(newCam.title) tại (\(newCam.latitude), \(newCam.longitude))")
    }
    
    /// Cập nhật thông tin tên đường / ghi chú và tốc độ giới hạn cho Camera đã lưu
    public func updateCamera(id: String, title: String, speedLimit: Int?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? "No name" : trimmed
        manuallyEditedCameraIds.insert(id)
        
        if let index = localCameras.firstIndex(where: { $0.id == id }) {
            localCameras[index].title = finalTitle
            localCameras[index].speedLimitKmh = speedLimit
            saveLocalCamerasToDisk()
            rebuildAllCamerasList()
            
            if lastPinnedCamera?.id == id {
                lastPinnedCamera = localCameras[index]
            }
            if activeWarningCamera?.id == id {
                activeWarningCamera = localCameras[index]
            }
            notifyMessage("Đã lưu tên camera: \(finalTitle)", duration: 4.0)
        }
    }
    
    /// Tập trung bản đồ tại vị trí Camera để người dùng kiểm tra
    public func focusMapOnCamera(_ camera: TrafficCamera) {
        isInspectingCameraLocation = true
        NotificationCenter.default.post(name: NSNotification.Name("FocusMapOnCamera"), object: camera)
    }
    
    /// Đưa bản đồ quay về theo dõi vị trí xe hiện tại
    public func returnToUserTracking() {
        isInspectingCameraLocation = false
        NotificationCenter.default.post(name: NSNotification.Name("RecenterMapOnUser"), object: nil)
    }
    
    /// Phân giải tọa độ thành tên đường hoặc địa chỉ gần đúng, trả về "No name" nếu không tìm thấy
    public func resolveStreetAddress(for coordinate: CLLocationCoordinate2D, completion: @escaping (String) -> Void) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        var didFinish = false
        let lock = NSLock()
        
        let finishOnce: (String) -> Void = { result in
            lock.lock()
            defer { lock.unlock() }
            guard !didFinish else { return }
            didFinish = true
            DispatchQueue.main.async {
                completion(result)
            }
        }
        
        // Giới hạn chờ tối đa 4 giây để tránh treo khi mạng yếu hoặc offline
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4.0) {
            finishOnce("No name")
        }
        
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "vi_VN")) { placemarks, error in
            guard error == nil, let placemark = placemarks?.first else {
                finishOnce("No name")
                return
            }
            let address = Self.formatStreetAddress(from: placemark)
            finishOnce(address)
        }
    }
    
    /// Ghép tên đường / địa chỉ gần đúng từ CLPlacemark, fallback "No name"
    private static func formatStreetAddress(from placemark: CLPlacemark) -> String {
        var parts: [String] = []
        
        let subThoroughfare = placemark.subThoroughfare?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let thoroughfare = placemark.thoroughfare?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = placemark.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let subLocality = placemark.subLocality?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let districtOrCity = (placemark.subAdministrativeArea ?? placemark.locality)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if !thoroughfare.isEmpty {
            if !subThoroughfare.isEmpty && !thoroughfare.lowercased().contains(subThoroughfare.lowercased()) {
                parts.append("\(subThoroughfare) \(thoroughfare)")
            } else {
                parts.append(thoroughfare)
            }
        } else if !name.isEmpty {
            parts.append(name)
        }
        
        if !subLocality.isEmpty && !parts.contains(where: { $0.localizedCaseInsensitiveContains(subLocality) }) {
            parts.append(subLocality)
        }
        
        if !districtOrCity.isEmpty && !parts.contains(where: { $0.localizedCaseInsensitiveContains(districtOrCity) }) {
            parts.append(districtOrCity)
        }
        
        let joined = parts.joined(separator: ", ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? "No name" : joined
    }
    
    /// Xóa một camera khỏi danh sách
    public func deleteCamera(id: String) {
        localCameras.removeAll { $0.id == id }
        osmCameras.removeAll { $0.id == id }
        if lastPinnedCamera?.id == id {
            lastPinnedCamera = nil
        }
        saveLocalCamerasToDisk()
        rebuildAllCamerasList()
        notifyMessage("Đã xóa camera giao thông")
    }
    
    // MARK: - Thuật toán Đánh giá Cự ly & Phát Cảnh Báo (Mặc định 150m)
    
    private func evaluateCameraProximity(currentLocation: CLLocation) {
        guard AppSettings.shared.isCameraWarningEnabled else {
            if isCameraWarningActive {
                isCameraWarningActive = false
                activeWarningCamera = nil
                warningDistanceMeters = 0
                HardwareService.shared.sendCommand(.cameraWarningOff)
            }
            return
        }
        guard !allCameras.isEmpty else { return }
        
        let threshold = warningThresholdMeters
        
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
        
        // KIỂM TRA ĐIỀU KIỆN TRONG VÙNG CẢNH BÁO (Mặc định <= 150 mét)
        if minDistance <= threshold {
            warningDistanceMeters = Int(minDistance)
            activeWarningCamera = nearest
            
            // Kích hoạt phát cảnh báo lần đầu khi tiến vào vùng cài đặt
            if activeWarningCameraId != nearest.id {
                activeWarningCameraId = nearest.id
                isCameraWarningActive = true
                
                print("CẢNH BÁO CAMERA GIAO THÔNG! Cự ly: \(Int(minDistance))m <= \(Int(threshold))m -> BẬT ĐÈN SỐ 3 TRÊN ESP32")
                
                // 1. GỬI LỆNH ĐẾN ESP32 ĐỂ MỞ ĐÈN SỐ 3
                HardwareService.shared.sendCommand(.cameraWarningOn)
                
                // 2. PHÁT ÂM THANH CẢNH BÁO TIẾNG VIỆT
                if AppSettings.shared.isSoundAlertEnabled {
                    let speedText = nearest.speedLimitKmh != nil ? ", giới hạn \(nearest.speedLimitKmh!) kilomet trên giờ" : ""
                    let alertSpeech = "Chú ý, phía trước \(Int(threshold)) mét có camera giao thông\(speedText), vui lòng chú ý tốc độ!"
                    speak(alertSpeech)
                }
                
                // Phản hồi rung cảnh báo
                if AppSettings.shared.isHapticFeedbackEnabled {
                    let feedback = UINotificationFeedbackGenerator()
                    feedback.notificationOccurred(.warning)
                }
            }
        } else {
            // Khi xe đã ra khỏi vùng cảnh báo
            if isCameraWarningActive && minDistance > (threshold + 40.0) {
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
    
    private func notifyMessage(_ msg: String, duration: TimeInterval = 3.5) {
        actionMessageWorkItem?.cancel()
        self.lastActionMessage = msg
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.lastActionMessage == msg {
                self.lastActionMessage = nil
                self.lastPinnedCamera = nil
            }
        }
        actionMessageWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
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
