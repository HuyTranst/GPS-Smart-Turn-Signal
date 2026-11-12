import SwiftUI

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
            
            // 2. Lớp giao diện HUD điều khiển nổi
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
                
                // Cột nút nổi bên phải: Ghim Camera và Định vị lại tâm xe
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        // NÚT ĐỊNH VỊ & GHI NHỚ CAMERA GIAO THÔNG (1 chạm tức thì + tự dò tên đường)
                        Button(action: {
                            cameraManager.saveCameraAtCurrentLocation()
                        }) {
                            VStack(spacing: 3) {
                                Image(systemName: "camera.badge.plus")
                                    .font(.system(size: 18, weight: .bold))
                                Text("Ghim Cam")
                                    .font(.system(size: 9, weight: .black))
                            }
                            .foregroundColor(.white)
                            .frame(width: 52, height: 52)
                            .background(
                                LinearGradient(colors: [Color.orange, Color.red], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .shadow(color: .orange.opacity(0.6), radius: 6, x: 0, y: 3)
                        }
                        
                        // Nút Recenter đưa bản đồ về tâm xe (nổi bật khi đang xem vị trí camera)
                        Button(action: {
                            cameraManager.returnToUserTracking()
                        }) {
                            VStack(spacing: 2) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 16, weight: .bold))
                                if cameraManager.isInspectingCameraLocation {
                                    Text("Về xe")
                                        .font(.system(size: 8, weight: .black))
                                }
                            }
                            .foregroundColor(.white)
                            .frame(width: cameraManager.isInspectingCameraLocation ? 52 : 44,
                                   height: cameraManager.isInspectingCameraLocation ? 52 : 44)
                            .background(cameraManager.isInspectingCameraLocation ? Color.blue : Color.black.opacity(0.85))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(cameraManager.isInspectingCameraLocation ? 0.9 : 0.3), lineWidth: cameraManager.isInspectingCameraLocation ? 2 : 1))
                            .shadow(radius: 4)
                        }
                    }
                }
                .padding(.trailing, 4)
                
                // Đèn xi nhan nhấp nháy mô phỏng taplo xe
                TurnIndicatorWidget()
                    .padding(.horizontal)
                    .padding(.bottom, 2)
                
                // Cụm phím điều khiển chạm nhanh & khẩn cấp khi thấy chốt CSGT
                bottomEmergencyControlBar
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
        .onAppear {
            locationManager.requestPermissions()
            locationManager.startTracking()
            hardware.configureActiveMode()
            navigation.startFreeRideProtection()
        }
    }
    
    // MARK: - Subviews
    
    /// Thanh trạng thái phía trên: Tốc độ, GPS, ESP32
    private var topStatusBar: some View {
        HStack(spacing: 10) {
            // Đồng hồ tốc độ GPS lớn
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(Int(locationManager.currentSpeedKmh))")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("km/h")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.85))
            .cornerRadius(12)
            
            Spacer()
            
            // Trạng thái kết nối ESP32
            Button(action: { showingHardwareTest = true }) {
                HStack(spacing: 6) {
                    Image(systemName: settings.connectionMode == .bluetooth ? "antenna.radiowaves.left.and.right" : "wifi")
                        .foregroundColor(hardware.connectionStatus == .connected ? .green : .red)
                    Circle()
                        .fill(hardware.connectionStatus == .connected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(hardware.connectionStatus == .connected ? "ESP32 SẴN SÀNG" : "MẤT KẾT NỐI")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.85))
                .cornerRadius(12)
            }
            
            // La bàn hướng di chuyển
            HStack(spacing: 4) {
                Image(systemName: "location.north.line.fill")
                    .rotationEffect(.degrees(locationManager.currentCourse))
                    .foregroundColor(.yellow)
                Text("\(Int(locationManager.currentCourse))°")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.85))
            .cornerRadius(12)
        }
    }
    
    /// Banner trạng thái giám sát ngã rẽ và CẢNH BÁO CAMERA GIAO THÔNG 500M
    private var statusAlertBanner: some View {
        VStack(spacing: 4) {
            // 1. ƯU TIÊN SỐ 1: CẢNH BÁO CAMERA GIAO THÔNG KHI CÁCH <= 500M
            if cameraManager.isCameraWarningActive, let cam = cameraManager.activeWarningCamera {
                HStack(spacing: 10) {
                    Image(systemName: "camera.badge.ellipsis")
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.yellow)
                    
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
    
    /// Cụm phím điều khiển chạm nhanh 50m tránh chốt phạt
    private var bottomEmergencyControlBar: some View {
        VStack(spacing: 8) {
            // Hàng phím to bấm nhanh bằng ngón cái khi đang lái xe
            HStack(spacing: 10) {
                // Phím Kích Hoạt Xi Nhan Trái Khẩn Cấp
                Button(action: {
                    controller.triggerManual(state: .left)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrowtriangle.backward.fill")
                            .font(.title3.bold())
                        Text("RẼ TRÁI")
                            .font(.system(size: 16, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(controller.currentState == .left ? Color.green : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                
                // Phím Tắt Khẩn Cấp Toàn Bộ Relay
                if controller.currentState != .off || cameraManager.isCameraWarningActive {
                    Button(action: {
                        controller.turnOff()
                        if cameraManager.isCameraWarningActive {
                            hardware.sendCommand(.cameraWarningOff)
                            cameraManager.isCameraWarningActive = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .frame(width: 50, height: 50)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                }
                
                // Phím Kích Hoạt Xi Nhan Phải Khẩn Cấp
                Button(action: {
                    controller.triggerManual(state: .right)
                }) {
                    HStack(spacing: 6) {
                        Text("RẼ PHẢI")
                            .font(.system(size: 16, weight: .heavy))
                        Image(systemName: "arrowtriangle.forward.fill")
                            .font(.title3.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(controller.currentState == .right ? Color.green : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
            }
            
            // Thanh công cụ phụ: Bản đồ Offline, Camera giao thông, Kiểm tra ESP32, Cài đặt
            HStack(spacing: 8) {
                toolButton(title: "Camera", icon: "camera.fill") { showingCameraList = true }
                toolButton(title: "Bản đồ Offline", icon: "map.fill") { showingOfflineMaps = true }
                toolButton(title: "Test ESP32", icon: "cpu") { showingHardwareTest = true }
                toolButton(title: "Cài đặt", icon: "gearshape.fill") { showingSettings = true }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.85))
        .cornerRadius(18)
    }
    
    private func toolButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.12))
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }
}
