import SwiftUI
import CoreLocation

/// Màn hình điều khiển chính (Dashboard) tự động bảo vệ tài xế khi qua ngã rẽ và cảnh báo Camera giao thông 500m
public struct MainDashboardView: View {
    @ObservedObject var locationManager = LocationManager.shared
    @ObservedObject var navigation = NavigationEngine.shared
    @ObservedObject var hardware = HardwareService.shared
    @ObservedObject var controller = TurnSignalController.shared
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var cameraManager = TrafficCameraManager.shared
    
    // Quản lý các sheet điều hướng
    @State private var showingSettings = false
    @State private var showingHardwareTest = false
    @State private var showingOfflineMaps = false
    @State private var showingRoutePlanner = false
    @State private var showingCameraList = false
    @State private var quickCameraEditorMode: CameraEditorMode? = nil
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // 1. Bản đồ OpenStreetMap toàn màn hình - Hiển thị xe và các Marker Camera
            OfflineMapView()
                .edgesIgnoringSafeArea(.all)
            
            // 2. Tâm ngắm cắm cờ khi người dùng kéo rê bản đồ hoặc chọn điểm
            if cameraManager.isMapPannedAwayFromUser || cameraManager.isInspectingCameraLocation || cameraManager.isPinpointModeActive {
                VStack(spacing: 4) {
                    // Tag tọa độ nổi trên đầu cây ghim
                    if let centerCoord = cameraManager.currentMapCenterCoordinate {
                        Text("📍 \(String(format: "%.4f, %.4f", centerCoord.latitude, centerCoord.longitude))")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.85))
                            .cornerRadius(10)
                            .shadow(radius: 3)
                    }
                    
                    // Cây ghim Camera CCTV chỉ chính xác vào tâm bản đồ
                    ZStack(alignment: .bottom) {
                        Circle()
                            .stroke(Color.orange, lineWidth: 2)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.orange.opacity(0.18)))
                        
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        
                        CCTVCameraIconView(size: 26, color: .orange)
                            .offset(y: -22)
                            .shadow(color: .black.opacity(0.5), radius: 3)
                    }
                    .frame(height: 54)
                }
            }
            
            // 3. Card thông tin chi tiết camera khi nhấp vào marker camera trên bản đồ
            if let selectedCam = cameraManager.selectedMapCamera {
                VStack {
                    Spacer()
                    selectedCameraDetailCard(selectedCam)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 140)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
            // 4. Lớp giao diện HUD điều khiển nổi
            VStack(spacing: 10) {
                // Header phía trên: Đồng hồ tốc độ lớn, GPS và Trạng thái ESP32
                topStatusBar
                    .sheet(item: $quickCameraEditorMode) { mode in
                        CameraEditorSheet(mode: mode)
                    }
                
                // Banner Cảnh Báo Camera Giao Thông hoặc Ngã Rẽ Thời Gian Thực
                statusAlertBanner
                
                // Toast thông báo hành động (kèm nút Sửa tên nhanh ngay sau khi ghim)
                if let msg = cameraManager.lastActionMessage {
                    HStack(spacing: 8) {
                        Text(msg)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        
                        if let pinned = cameraManager.lastPinnedCamera {
                            Button(action: {
                                quickCameraEditorMode = .edit(camera: pinned)
                            }) {
                                Text("Sửa tên")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.yellow)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.88))
                    .cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.yellow.opacity(0.8), lineWidth: 1.5))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer()
                
                // Cột nút nổi bên phải: Ghim Xe, Ghim Cam (thay nút Cần Thơ), Định vị lại tâm xe
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        // 1. NÚT GHIM TẠI XE HIỆN TẠI (Dùng khi đang lái xe ngoài đường)
                        Button(action: {
                            if let loc = locationManager.currentLocation?.coordinate {
                                quickCameraEditorMode = .create(coordinate: loc)
                            } else {
                                cameraManager.saveCameraAtCurrentLocation()
                            }
                        }) {
                            VStack(spacing: 2) {
                                Image(systemName: "location.north.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                                Text("Ghim Xe")
                                    .font(.system(size: 8, weight: .black))
                            }
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                            .shadow(radius: 4)
                        }
                        
                        // 2. NÚT GHIM CAM (Thay thế nút Cần Thơ - Đánh dấu camera tại tâm bản đồ đang ngắm)
                        Button(action: {
                            if let center = cameraManager.currentMapCenterCoordinate {
                                quickCameraEditorMode = .create(coordinate: center)
                            } else if let loc = locationManager.currentLocation?.coordinate {
                                quickCameraEditorMode = .create(coordinate: loc)
                            } else {
                                cameraManager.saveCameraAtCurrentLocation()
                            }
                        }) {
                            VStack(spacing: 2) {
                                CCTVCameraIconView(size: 18, color: .white)
                                Text("Ghim Cam")
                                    .font(.system(size: 8, weight: .black))
                            }
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(
                                LinearGradient(colors: [Color.orange, Color.red], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                            .shadow(color: .orange.opacity(0.6), radius: 5, x: 0, y: 2)
                        }
                        
                        // 3. NÚT RECENTER QUAY VỀ THEO DÕI XE
                        if cameraManager.isMapPannedAwayFromUser || cameraManager.isInspectingCameraLocation || cameraManager.isPinpointModeActive {
                            Button(action: {
                                cameraManager.returnToUserTracking()
                            }) {
                                VStack(spacing: 2) {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 16, weight: .bold))
                                    Text("Về xe")
                                        .font(.system(size: 8, weight: .black))
                                }
                                .foregroundColor(.white)
                                .frame(width: 46, height: 46)
                                .background(Color.black.opacity(0.85))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.cyan, lineWidth: 2))
                                .shadow(radius: 4)
                            }
                        }
                    }
                }
                .padding(.trailing, 4)
                
                // 2 Button RẼ TRÁI và RẼ PHẢI nằm sát về 2 bên phía dưới cùng màn hình
                HStack(alignment: .bottom) {
                    // Button TRÁI sát mép trái
                    Button(action: {
                        if controller.currentState == .left {
                            controller.turnOff()
                        } else {
                            controller.triggerManual(state: .left)
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrowtriangle.backward.fill")
                                .font(.system(size: 22, weight: .black))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("TRÁI")
                                    .font(.system(size: 16, weight: .heavy))
                                if controller.currentState == .left {
                                    Text("\(controller.remainingSeconds)s")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                }
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(controller.currentState == .left ? Color.green : Color.black.opacity(0.85))
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(controller.currentState == .left ? Color.white : Color.white.opacity(0.3), lineWidth: 1.8)
                        )
                        .shadow(color: controller.currentState == .left ? Color.green.opacity(0.8) : Color.black.opacity(0.4), radius: 6)
                    }
                    
                    Spacer()
                    
                    // Nút tắt xi nhan nhanh ở giữa nếu đang bật
                    if controller.currentState != .off || cameraManager.isCameraWarningActive {
                        Button(action: {
                            controller.turnOff()
                            if cameraManager.isCameraWarningActive {
                                hardware.sendCommand(.cameraWarningOff)
                                cameraManager.isCameraWarningActive = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.red)
                                .clipShape(Circle())
                                .shadow(color: Color.red.opacity(0.6), radius: 5)
                        }
                    }
                    
                    Spacer()
                    
                    // Button PHẢI sát mép phải
                    Button(action: {
                        if controller.currentState == .right {
                            controller.turnOff()
                        } else {
                            controller.triggerManual(state: .right)
                        }
                    }) {
                        HStack(spacing: 8) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("PHẢI")
                                    .font(.system(size: 16, weight: .heavy))
                                if controller.currentState == .right {
                                    Text("\(controller.remainingSeconds)s")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                }
                            }
                            Image(systemName: "arrowtriangle.forward.fill")
                                .font(.system(size: 22, weight: .black))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(controller.currentState == .right ? Color.green : Color.black.opacity(0.85))
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(controller.currentState == .right ? Color.white : Color.white.opacity(0.3), lineWidth: 1.8)
                        )
                        .shadow(color: controller.currentState == .right ? Color.green.opacity(0.8) : Color.black.opacity(0.4), radius: 6)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 14)
            .padding(.top, 44) // Tránh Dynamic Island / Tai thỏ
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $showingHardwareTest) { HardwareTestView() }
        .sheet(isPresented: $showingOfflineMaps) { OfflineMapManagerView() }
        .sheet(isPresented: $showingRoutePlanner) { RoutePlannerView() }
        .sheet(isPresented: $showingCameraList) { TrafficCameraListView() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PinCameraAtCoordinate"))) { notif in
            if let dict = notif.object as? [String: Double],
               let lat = dict["latitude"],
               let lon = dict["longitude"] {
                quickCameraEditorMode = .create(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EditCameraNotification"))) { notif in
            if let cam = notif.object as? TrafficCamera {
                quickCameraEditorMode = .edit(camera: cam)
            }
        }
        .onAppear {
            locationManager.requestPermissions()
            locationManager.startTracking()
            hardware.configureActiveMode()
            navigation.startFreeRideProtection()
        }
    }
    
    // MARK: - Subviews
    
    /// Card chi tiết camera khi người dùng nhấp vào điểm marker trên bản đồ
    private func selectedCameraDetailCard(_ cam: TrafficCamera) -> some View {
        HStack(spacing: 12) {
            CCTVCameraIconView(size: 26, color: .orange)
                .frame(width: 42, height: 42)
                .background(Color.orange.opacity(0.2))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 3) {
                Text(cam.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    if let loc = locationManager.currentLocation {
                        let dist = Int(loc.distance(from: CLLocation(latitude: cam.latitude, longitude: cam.longitude)))
                        Text("Cách xe: \(dist)m")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(dist <= Int(AppSettings.shared.cameraWarningDistanceMeters) ? .red : .yellow)
                    }
                    if let speed = cam.speedLimitKmh {
                        Text("• Tối đa: \(speed) km/h")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            // Nút sửa tên
            Button(action: {
                quickCameraEditorMode = .edit(camera: cam)
            }) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
            }
            
            // Nút đóng
            Button(action: {
                cameraManager.selectedMapCamera = nil
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.92))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.8), lineWidth: 1.5))
        .shadow(color: .orange.opacity(0.4), radius: 8)
    }
    
    /// Thanh trạng thái phía trên: Tốc độ, GPS, ESP32 và Nút Cài Đặt (Bánh Răng Cưa)
    private var topStatusBar: some View {
        HStack(spacing: 8) {
            // Đồng hồ tốc độ GPS lớn
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(Int(locationManager.currentSpeedKmh))")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("km/h")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.85))
            .cornerRadius(12)
            
            Spacer()
            
            // Trạng thái kết nối ESP32
            HStack(spacing: 5) {
                Image(systemName: settings.connectionMode == .bluetooth ? "antenna.radiowaves.left.and.right" : "wifi")
                    .foregroundColor(hardware.connectionStatus == .connected ? .green : .red)
                    .font(.system(size: 12))
                Circle()
                    .fill(hardware.connectionStatus == .connected ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                Text(hardware.connectionStatus == .connected ? "ESP32" : "MẤT KẾT NỐI")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.85))
            .cornerRadius(12)
            
            // La bàn hướng di chuyển
            HStack(spacing: 3) {
                Image(systemName: "location.north.line.fill")
                    .rotationEffect(.degrees(locationManager.currentCourse))
                    .foregroundColor(.yellow)
                    .font(.system(size: 12))
                Text("\(Int(locationManager.currentCourse))°")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.85))
            .cornerRadius(12)
            
            // Nút Bánh Răng Cưa Cài Đặt (Góc trên bên phải)
            Button(action: {
                showingSettings = true
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.2))
                    .shadow(radius: 4)
            }
        }
    }
    
    /// Banner trạng thái giám sát ngã rẽ và CẢNH BÁO CAMERA GIAO THÔNG 500M
    private var statusAlertBanner: some View {
        VStack(spacing: 4) {
            // 1. ƯU TIÊN SỐ 1: CẢNH BÁO CAMERA GIAO THÔNG KHI CÁCH <= 500M
            if cameraManager.isCameraWarningActive, let cam = cameraManager.activeWarningCamera {
                HStack(spacing: 10) {
                    CCTVCameraIconView(size: 26, color: .yellow)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("CẢNH BÁO CAMERA GIAO THÔNG!")
                                .font(.system(size: 13, weight: .black))
                            Spacer()
                            Text("\(cameraManager.warningDistanceMeters)m")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundColor(.yellow)
                        }
                        
                        Text("ĐÃ GỬI LỆNH MỞ ĐÈN SỐ 3 TRÊN ESP32")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(Color.red)
                .cornerRadius(14)
                .shadow(color: .red.opacity(0.7), radius: 10)
            }
            // 2. CẢNH BÁO ĐANG RẼ TRÁI
            else if controller.currentState == .left {
                HStack(spacing: 8) {
                    Image(systemName: "arrowtriangle.backward.fill")
                        .font(.title2.bold())
                    Text("ĐANG RẼ TRÁI - XI NHAN ĐANG BẬT!")
                        .font(.headline.bold())
                    Image(systemName: "arrowtriangle.backward.fill")
                        .font(.title2.bold())
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.green)
                .cornerRadius(12)
                .shadow(color: .green.opacity(0.5), radius: 8)
            }
            // 3. CẢNH BÁO ĐANG RẼ PHẢI
            else if controller.currentState == .right {
                HStack(spacing: 8) {
                    Image(systemName: "arrowtriangle.forward.fill")
                        .font(.title2.bold())
                    Text("ĐANG RẼ PHẢI - XI NHAN ĐANG BẬT!")
                        .font(.headline.bold())
                    Image(systemName: "arrowtriangle.forward.fill")
                        .font(.title2.bold())
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.green)
                .cornerRadius(12)
                .shadow(color: .green.opacity(0.5), radius: 8)
            }
            // 4. TRẠNG THÁI BÌNH THƯỜNG
            else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text(navigation.alertBannerText)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.black.opacity(0.85))
                .cornerRadius(12)
            }
        }
    }
}
