import Foundation
import CoreLocation
import Combine
import AVFoundation
import AudioToolbox
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
    
    // Tương tác bản đồ: Camera được chọn xem chi tiết & Tâm bản đồ khi rê
    @Published public var selectedMapCamera: TrafficCamera? = nil
    @Published public var currentMapCenterCoordinate: CLLocationCoordinate2D? = nil
    @Published public var isMapPannedAwayFromUser: Bool = false
    @Published public var isPinpointModeActive: Bool = false
    
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
        loadBuiltinVietnamCamerasIfNeeded()
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
        selectedMapCamera = camera
        NotificationCenter.default.post(name: NSNotification.Name("FocusMapOnCamera"), object: camera)
    }
    
    /// Đưa bản đồ quay về theo dõi vị trí xe hiện tại
    public func returnToUserTracking() {
        isInspectingCameraLocation = false
        isMapPannedAwayFromUser = false
        isPinpointModeActive = false
        selectedMapCamera = nil
        NotificationCenter.default.post(name: NSNotification.Name("RecenterMapOnUser"), object: nil)
    }
    
    /// Dời bản đồ đến trung tâm TP. Cần Thơ để xem và ghim camera offline
    public func focusMapOnCanTho() {
        let canThoCoord = CLLocationCoordinate2D(latitude: 10.0345, longitude: 105.7842)
        focusMapOnCoordinate(coordinate: canThoCoord, title: "TP. Cần Thơ")
    }
    
    /// Dời bản đồ đến trung tâm TP. Sóc Trăng để xem và ghim camera offline
    public func focusMapOnSocTrang() {
        let socTrangCoord = CLLocationCoordinate2D(latitude: 9.6015, longitude: 105.9752)
        focusMapOnCoordinate(coordinate: socTrangCoord, title: "TP. Sóc Trăng")
    }
    
    /// Dời bản đồ đến một tọa độ thành phố bất kỳ
    public func focusMapOnCoordinate(coordinate: CLLocationCoordinate2D, title: String? = nil) {
        isInspectingCameraLocation = true
        isMapPannedAwayFromUser = true
        isPinpointModeActive = true
        currentMapCenterCoordinate = coordinate
        NotificationCenter.default.post(
            name: NSNotification.Name("FocusMapOnCoordinate"),
            object: [
                "latitude": coordinate.latitude,
                "longitude": coordinate.longitude
            ]
        )
        if let title = title {
            notifyMessage("Đã dời bản đồ đến \(title)! Rê bản đồ để chọn ngã tư cần ghim.", duration: 3.5)
        }
    }
    
    /// Thử rung ngay theo cấu hình để người dùng kiểm tra độ rung của máy
    public func triggerTestCameraVibration() {
        let pulses = max(1, AppSettings.shared.cameraVibrationPulses)
        for i in 0..<pulses {
            let delay = Double(i) * 0.22
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
            }
        }
    }
    
    /// Ghim camera tại một tọa độ bất kỳ trên bản đồ (từ xa, không cần di chuyển đến nơi đó)
    public func saveCameraAtCoordinate(_ coordinate: CLLocationCoordinate2D, title: String? = nil, speedLimit: Int? = nil) {
        saveCameraAtCurrentLocation(title: title, speedLimit: speedLimit, customCoordinate: coordinate)
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
                stopRepeatingCameraHaptics()
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
                
                // 3. BẮT ĐẦU CHU KỲ RUNG 5 LẦN, NGHỈ 3S LẶP LẠI LIÊN TỤC CHO ĐẾN KHI RA KHỎI VÙNG
                startRepeatingCameraHaptics()
            }
        } else {
            // Khi xe đã ra khỏi vùng cảnh báo
            if isCameraWarningActive && minDistance > (threshold + 40.0) {
                print("Đã ra khỏi vùng camera -> TẮT ĐÈN SỐ 3 TRÊN ESP32 & DỪNG RUNG")
                isCameraWarningActive = false
                stopRepeatingCameraHaptics()
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
    
    // MARK: - Quản Lý Rung Chu Kỳ Cảnh Báo Camera (Rung 5 lần, nghỉ 3 giây)
    
    private var cameraVibrationTimer: Timer?
    private var cameraVibrationWorkItems: [DispatchWorkItem] = []
    
    private func startRepeatingCameraHaptics() {
        stopRepeatingCameraHaptics()
        guard AppSettings.shared.isHapticFeedbackEnabled,
              AppSettings.shared.isCameraRepeatingVibrationEnabled else { return }
        
        // Phát ngay đợt rung đầu tiên
        executeCameraVibrationBurst()
        
        // Tính tổng chu kỳ lặp = (số nhịp - 1) * 0.22s + thời gian nghỉ cài đặt (mặc định 3.0s)
        let pulses = max(1, AppSettings.shared.cameraVibrationPulses)
        let burstDuration = Double(pulses - 1) * 0.22
        let cycleDuration = burstDuration + max(1.0, AppSettings.shared.cameraVibrationPauseSeconds)
        
        let timer = Timer(timeInterval: cycleDuration, repeats: true) { [weak self] _ in
            guard let self = self, self.isCameraWarningActive else {
                self?.stopRepeatingCameraHaptics()
                return
            }
            self.executeCameraVibrationBurst()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.cameraVibrationTimer = timer
    }
    
    private func executeCameraVibrationBurst() {
        guard isCameraWarningActive else { return }
        let pulses = max(1, AppSettings.shared.cameraVibrationPulses)
        
        for i in 0..<pulses {
            let delay = Double(i) * 0.22
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.isCameraWarningActive else { return }
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
            }
            cameraVibrationWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }
    
    private func stopRepeatingCameraHaptics() {
        cameraVibrationTimer?.invalidate()
        cameraVibrationTimer = nil
        cameraVibrationWorkItems.forEach { $0.cancel() }
        cameraVibrationWorkItems.removeAll()
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
    
    public func saveOsmCacheToDisk() {
        do {
            let data = try JSONEncoder().encode(osmCameras)
            try data.write(to: osmCacheFileURL, options: .atomic)
        } catch {
            print("Lỗi lưu file cache OSM camera: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Dữ Liệu Camera Giao Thông Trọng Điểm Việt Nam Dùng Offline Sẵn
    
    /// BỘ DỮ LIỆU CAMERA GIAO THÔNG & PHẠT NGUỘI CẦN THƠ - SÓC TRĂNG (ĐỒNG BẰNG SÔNG CỬU LONG)
    public static let canThoSocTrangPresets: [TrafficCamera] = [
        // 12 NÚT GIAO THÔNG & CAMERA AI PHẠT NGUỘI TP. CẦN THƠ
        TrafficCamera(id: "ct_01", latitude: 10.0526, longitude: 105.7725, title: "[Cần Thơ] Nút giao Cách Mạng Tháng 8 - Nguyễn Văn Cừ (Camera AI phạt nguội)", speedLimitKmh: 50, sourceType: .openStreetMap),
        TrafficCamera(id: "ct_02", latitude: 10.0381, longitude: 105.7876, title: "[Cần Thơ] Nút giao Nguyễn Trãi - Cầu Ninh Kiều (Camera phạt nguội vượt đèn & ngược chiều)", speedLimitKmh: 50, sourceType: .openStreetMap),
        TrafficCamera(id: "ct_03", latitude: 10.0468, longitude: 105.7663, title: "[Cần Thơ] Nút giao Nguyễn Văn Cừ - Võ Văn Kiệt - Mậu Thân (Camera AI phạt nguội)", speedLimitKmh: 50, sourceType: .openStreetMap),
        TrafficCamera(id: "ct_04", latitude: 10.0327, longitude: 105.7702, title: "[Cần Thơ] Nút giao Trần Hưng Đạo - Mậu Thân - 3 Tháng 2 (Camera giám sát tín hiệu đèn & chuyển làn)", speedLimitKmh: 50, sourceType: .openStreetMap),
        TrafficCamera(id: "ct_05", latitude: 10.0245, longitude: 105.7735, title: "[Cần Thơ] Nút giao Mậu Thân - 30 Tháng 4 (Camera giám sát đèn tín hiệu)", speedLimitKmh: 50, sourceType: .openStreetMap),
        TrafficCamera(id: "ct_06", latitude: 10.0229, longitude: 105.7562, title: "[Cần Thơ] Nút giao Nguyễn Văn Linh - Nguyễn Văn Cừ (Camera AI giám sát nút giao)", speedLimitKmh: 50, sourceType: .openStreetMap),
        TrafficCamera(id: "ct_07", latitude: 10.0175, longitude: 105.7651, title: "[Cần Thơ] Nút giao Nguyễn Văn Linh - 3 Tháng 2 (Camera giám sát xe tải & phạt nguội)", speedLimitKmh: 50, sourceType: .openStreetMap),
        TrafficCamera(id: "ct_08", latitude: 10.0134, longitude: 105.7728, title: "[Cần Thơ] Nút giao Nguyễn Văn Linh - 30 Tháng 4 (Camera AI phạt nguội)", speedLimitKmh: 50, sourceType: .openStreetMap),
        TrafficCamera(id: "ct_09", latitude: 10.0183, longitude: 105.7947, title: "[Cần Thơ] Cụm Nút giao IC3-1 (Võ Nguyên Giáp - Quang Trung) (Camera đo tốc độ & phạt nguội cửa ngõ)", speedLimitKmh: 60, sourceType: .openStreetMap),
        TrafficCamera(id: "ct_10", latitude: 10.0162, longitude: 105.7961, title: "[Cần Thơ] Cụm Nút giao IC3-2 (Võ Nguyên Giáp hướng cầu Cần Thơ) (Camera đo tốc độ tự động)", speedLimitKmh: 60, sourceType: .openStreetMap),
        TrafficCamera(id: "ct_11", latitude: 9.9922, longitude: 105.7778, title: "[Cần Thơ] Nút giao IC4 (Quốc lộ 1A - Đường Hậu Giang) (Camera giám sát tốc độ & tải trọng QL1A)", speedLimitKmh: 60, sourceType: .openStreetMap),
        TrafficCamera(id: "ct_12", latitude: 10.0220, longitude: 105.7860, title: "[Cần Thơ] Đầu Cầu Quang Trung (Đại lộ Hòa Bình - 30/4) (Camera giám sát giao thông đô thị)", speedLimitKmh: 50, sourceType: .openStreetMap),
        TrafficCamera(id: "vn_ct_cau_ct", latitude: 10.0075, longitude: 105.8115, title: "[Cần Thơ] Nút giao Cầu Cần Thơ - Quốc lộ 1A (Bờ Cái Răng)", speedLimitKmh: 80, sourceType: .openStreetMap),
        TrafficCamera(id: "vn_ct_nam_song_hau", latitude: 9.9820, longitude: 105.8180, title: "[Cần Thơ] Tuyến Nam Sông Hậu - Nút giao Cảng Cái Cui, Cái Răng", speedLimitKmh: 60, sourceType: .openStreetMap),
        
        // 8 NÚT GIAO THÔNG & CAMERA AI PHẠT NGUỘI TỈNH SÓC TRĂNG
        TrafficCamera(id: "st_01", latitude: 9.6015, longitude: 105.9752, title: "[Sóc Trăng] Nút giao Lê Duẩn - Lê Hồng Phong (Camera giám sát đèn tín hiệu thông minh)", speedLimitKmh: 50, sourceType: .openStreetMap),
        TrafficCamera(id: "st_02", latitude: 9.6052, longitude: 105.9721, title: "[Sóc Trăng] Đường Trần Hưng Đạo - Hùng Vương (Camera phạt nguội tốc độ & làn đường)", speedLimitKmh: 50, sourceType: .openStreetMap),
        TrafficCamera(id: "st_03", latitude: 9.6080, longitude: 105.9685, title: "[Sóc Trăng] Nút giao Dương Kỳ Hiệp - Trần Hưng Đạo (Camera phạt nguội vượt đèn tín hiệu)", speedLimitKmh: 50, sourceType: .openStreetMap),
        TrafficCamera(id: "st_04", latitude: 9.6041, longitude: 105.9803, title: "[Sóc Trăng] Đường Lý Thường Kiệt (Gần khu vực chợ trung tâm) (Camera giám sát dừng đỗ)", speedLimitKmh: 40, sourceType: .openStreetMap),
        TrafficCamera(id: "st_05", latitude: 9.6150, longitude: 105.9520, title: "[Sóc Trăng] Tuyến đường tránh Võ Văn Kiệt (QL1A cũ) (Camera đo tốc độ tự động 24/7)", speedLimitKmh: 60, sourceType: .openStreetMap),
        TrafficCamera(id: "st_06", latitude: 9.5850, longitude: 105.9850, title: "[Sóc Trăng] Quốc lộ 1A - Đoạn Ngã 3 Trà Tim (Camera AI phạt nguội cửa ngõ phía Nam)", speedLimitKmh: 60, sourceType: .openStreetMap),
        TrafficCamera(id: "st_07", latitude: 9.6450, longitude: 105.9250, title: "[Sóc Trăng] Quốc lộ 1A - Cửa ngõ Châu Thành vào TP. Sóc Trăng (Camera giám sát tốc độ tự động)", speedLimitKmh: 80, sourceType: .openStreetMap),
        TrafficCamera(id: "st_08", latitude: 9.6095, longitude: 105.9610, title: "[Sóc Trăng] Ngã tư Quốc lộ 1A - Bến xe Sóc Trăng (Camera giám sát trật tự giao thông)", speedLimitKmh: 50, sourceType: .openStreetMap)
    ]
    
    /// Nạp dữ liệu camera giao thông Cần Thơ & Sóc Trăng để dùng offline không cần mạng
    public func loadCanThoSocTrangPresetCameras(notify: Bool = true) {
        var existingDict = [String: TrafficCamera]()
        for cam in self.osmCameras {
            existingDict[cam.id] = cam
        }
        for cam in Self.canThoSocTrangPresets {
            existingDict[cam.id] = cam
        }
        self.osmCameras = Array(existingDict.values).sorted(by: { $0.title < $1.title })
        saveOsmCacheToDisk()
        rebuildAllCamerasList()
        if notify {
            notifyMessage("Đã nạp \(Self.canThoSocTrangPresets.count) camera giao thông Cần Thơ & Sóc Trăng dùng offline!", duration: 4.0)
        }
    }
    
    public func loadCanThoPresetCameras(notify: Bool = true) {
        loadCanThoSocTrangPresetCameras(notify: notify)
    }
    
    public func loadBuiltinVietnamCamerasIfNeeded() {
        // Nếu bộ nhớ máy chưa có dữ liệu camera nào (hoặc lần đầu mở app), tự nạp bộ camera giao thông trọng điểm
        guard localCameras.isEmpty && osmCameras.isEmpty else { return }
        loadBuiltinVietnamPresetCameras(notify: false)
    }
    
    public func loadBuiltinVietnamPresetCameras(notify: Bool = true) {
        var presets: [TrafficCamera] = Self.canThoSocTrangPresets
        
        presets.append(contentsOf: [
            // TP. HỒ CHÍ MINH
            TrafficCamera(id: "vn-hcm-01", latitude: 10.7725, longitude: 106.6980, title: "Ngã tư Nam Kỳ Khởi Nghĩa - Lê Lợi, Q.1", speedLimitKmh: 50, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-hcm-02", latitude: 10.7511, longitude: 106.6782, title: "Đại lộ Võ Văn Kiệt - Cầu Chà Và, Q.5", speedLimitKmh: 60, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-hcm-03", latitude: 10.8228, longitude: 106.6874, title: "Đại lộ Phạm Văn Đồng - Phan Văn Trị, Gò Vấp", speedLimitKmh: 60, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-hcm-04", latitude: 10.7981, longitude: 106.7410, title: "Nút giao An Phú - Mai Chí Thọ, TP. Thủ Đức", speedLimitKmh: 60, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-hcm-05", latitude: 10.7302, longitude: 106.7078, title: "Đại lộ Nguyễn Văn Linh - Nguyễn Hữu Thọ, Q.7", speedLimitKmh: 60, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-hcm-06", latitude: 10.8523, longitude: 106.7721, title: "Xa lộ Hà Nội - Ngã tư Thủ Đức", speedLimitKmh: 60, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-hcm-07", latitude: 10.7852, longitude: 106.7758, title: "Đầu Cao tốc TP.HCM - Long Thành - Dầu Giây", speedLimitKmh: 100, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-hcm-08", latitude: 10.8265, longitude: 106.6190, title: "Quốc lộ 1A - Ngã tư An Sương, Q.12", speedLimitKmh: 60, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-hcm-09", latitude: 10.7540, longitude: 106.6020, title: "Quốc lộ 1A - Ngã tư Gò Mây, Bình Tân", speedLimitKmh: 60, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-hcm-10", latitude: 10.8810, longitude: 106.7780, title: "Đại lộ Phạm Văn Đồng - Cầu vượt Linh Xuân", speedLimitKmh: 60, sourceType: .openStreetMap),
            
            // HÀ NỘI
            TrafficCamera(id: "vn-hn-01", latitude: 21.0285, longitude: 105.8542, title: "Tràng Thi - Bà Triệu, Hoàn Kiếm", speedLimitKmh: 50, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-hn-02", latitude: 21.0135, longitude: 105.8080, title: "Nút giao Trần Duy Hưng - Hoàng Minh Giám, Cầu Giấy", speedLimitKmh: 50, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-hn-03", latitude: 20.9850, longitude: 105.8360, title: "Đường Vành Đai 3 - Ngã tư Giải Phóng", speedLimitKmh: 80, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-hn-04", latitude: 21.0020, longitude: 105.8450, title: "Đại Cồ Việt - Xã Đàn (Hầm Kim Liên)", speedLimitKmh: 50, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-hn-05", latitude: 20.9550, longitude: 105.8550, title: "Đầu Cao tốc Pháp Vân - Cầu Giẽ", speedLimitKmh: 100, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-hn-06", latitude: 21.0480, longitude: 105.7820, title: "Phạm Văn Đồng - Cầu Thăng Long", speedLimitKmh: 60, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-hn-07", latitude: 21.0370, longitude: 105.8820, title: "Đầu Cao tốc Hà Nội - Hải Phòng", speedLimitKmh: 120, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-hn-08", latitude: 21.0310, longitude: 105.8190, title: "Ngã tư Kim Mã - Liễu Giai, Ba Đình", speedLimitKmh: 50, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-hn-09", latitude: 21.0200, longitude: 105.7760, title: "Đại lộ Thăng Long - Lê Quang Đạo, Nam Từ Liêm", speedLimitKmh: 100, sourceType: .openStreetMap),
            
            // ĐÀ NẴNG
            TrafficCamera(id: "vn-dn-01", latitude: 16.0610, longitude: 108.2230, title: "Cầu Rồng - Đường 2 Tháng 9, Hải Châu", speedLimitKmh: 50, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-dn-02", latitude: 16.0750, longitude: 108.2210, title: "Đường Bạch Đằng - Lê Duẩn, Hải Châu", speedLimitKmh: 50, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-dn-03", latitude: 16.0600, longitude: 108.1720, title: "Ngã ba Huế - Tôn Đức Thắng, Liên Chiểu", speedLimitKmh: 60, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-dn-04", latitude: 16.0350, longitude: 108.2450, title: "Đường Võ Nguyên Giáp - Hồ Xuân Hương, Ngũ Hành Sơn", speedLimitKmh: 50, sourceType: .openStreetMap),
            TrafficCamera(id: "vn-dn-05", latitude: 16.0820, longitude: 108.2220, title: "Cầu Thuận Phước - Nguyễn Tất Thành", speedLimitKmh: 50, sourceType: .openStreetMap)
        ])
        
        self.osmCameras = presets
        saveOsmCacheToDisk()
        rebuildAllCamerasList()
        if notify {
            notifyMessage("Đã nạp \(presets.count) camera giao thông trọng điểm Việt Nam (gồm Cần Thơ, TP.HCM, Hà Nội, Đà Nẵng)!", duration: 4.0)
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm dd/MM"
        return formatter.string(from: date)
    }
}
