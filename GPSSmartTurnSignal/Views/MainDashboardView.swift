import SwiftUI

/// Màn hình điều khiển chính (Dashboard) tự động bảo vệ tài xế khi qua ngã rẽ
public struct MainDashboardView: View {
    @ObservedObject var locationManager = LocationManager.shared
    @ObservedObject var navigation = NavigationEngine.shared
    @ObservedObject var hardware = HardwareService.shared
    @ObservedObject var controller = TurnSignalController.shared
    @ObservedObject var settings = AppSettings.shared
    
    // Quản lý các sheet điều hướng
    @State private var showingSettings = false
    @State private var showingHardwareTest = false
    @State private var showingOfflineMaps = false
    @State private var showingRoutePlanner = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // 1. Bản đồ OpenStreetMap Offline toàn màn hình - Tự động định vị và xoay theo đầu xe
            OfflineMapView()
                .edgesIgnoringSafeArea(.all)
            
            // 2. Lớp giao diện HUD điều khiển nổi
            VStack(spacing: 12) {
                // Header phía trên: Đồng hồ tốc độ lớn, GPS và Trạng thái ESP32
                topStatusBar
                
                // Banner Cảnh Báo Trạng Thái Ngã Rẽ Thời Gian Thực
                statusAlertBanner
                
                Spacer()
                
                // Nút bấm định vị lại tâm xe và kích hoạt lại auto zoom
                HStack {
                    Spacer()
                    Button(action: {
                        NotificationCenter.default.post(name: NSNotification.Name("RecenterMapOnUser"), object: nil)
                    }) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.black.opacity(0.8))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                            .shadow(radius: 4)
                    }
                }
                .padding(.trailing, 4)
                
                // Đèn xi nhan nhấp nháy mô phỏng taplo xe
                TurnIndicatorWidget()
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                
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
        .onAppear {
            // TỰ ĐỘNG KHỞI CHẠY TOÀN BỘ NGAY KHI MỞ APP (KHÔNG CẦN BẤM NÚT NÀO)
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
            .background(Color.black.opacity(0.8))
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
                .background(Color.black.opacity(0.8))
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
            .background(Color.black.opacity(0.8))
            .cornerRadius(12)
        }
    }
    
    /// Banner trạng thái giám sát ngã rẽ thông minh
    private var statusAlertBanner: some View {
        VStack(spacing: 4) {
            if controller.currentState == .left {
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
            } else if controller.currentState == .right {
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
            } else {
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
                .background(Color.black.opacity(0.8))
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
                
                // Phím Tắt Khẩn Cấp
                if controller.currentState != .off {
                    Button(action: {
                        controller.turnOff()
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
            
            // Thanh công cụ phụ: Bản đồ Offline, Kiểm tra phần cứng, Cài đặt
            HStack(spacing: 10) {
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
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.12))
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }
}
