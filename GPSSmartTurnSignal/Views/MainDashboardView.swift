import SwiftUI

/// Màn hình điều khiển chính (Dashboard) chuẩn HUD dành cho tài xế khi gắn máy trên xe
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
            // 1. Bản đồ OpenStreetMap Offline toàn màn hình
            OfflineMapView()
                .edgesIgnoringSafeArea(.all)
            
            // 2. Lớp giao diện HUD điều khiển nổi
            VStack(spacing: 12) {
                // Header phía trên: Thông số tốc độ, GPS và Trạng thái ESP32
                topStatusBar
                
                // Thẻ chỉ dẫn ngã rẽ tiếp theo (Chỉ hiện khi đang dẫn đường)
                if navigation.isNavigating, let maneuver = navigation.currentManeuver {
                    maneuverCard(maneuver: maneuver)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer()
                
                // Đèn xi nhan nhấp nháy trực quan trên màn hình
                TurnIndicatorWidget()
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                
                // Thanh điều khiển hành trình và các nút chức năng
                bottomControlBar
            }
            .padding(.horizontal, 14)
            .padding(.top, 44) // Tránh tai thỏ/Dynamic Island
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $showingHardwareTest) { HardwareTestView() }
        .sheet(isPresented: $showingOfflineMaps) { OfflineMapManagerView() }
        .sheet(isPresented: $showingRoutePlanner) { RoutePlannerView() }
        .onAppear {
            locationManager.requestPermissions()
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
            .background(Color.black.opacity(0.75))
            .cornerRadius(12)
            
            Spacer()
            
            // Trạng thái ESP32
            Button(action: { showingHardwareTest = true }) {
                HStack(spacing: 6) {
                    Image(systemName: settings.connectionMode == .bluetooth ? "antenna.radiowaves.left.and.right" : "wifi")
                        .foregroundColor(hardware.connectionStatus == .connected ? .green : .red)
                    Circle()
                        .fill(hardware.connectionStatus == .connected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(hardware.connectionStatus == .connected ? "ESP32 SẴN SÀNG" : "MẤT ESP32")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.75))
                .cornerRadius(12)
            }
            
            // Chất lượng GPS
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
            .background(Color.black.opacity(0.75))
            .cornerRadius(12)
        }
    }
    
    /// Thẻ HUD hiển thị ngã rẽ và khoảng cách đếm ngược
    private func maneuverCard(maneuver: RouteManeuver) -> some View {
        HStack(spacing: 16) {
            // Biểu tượng mũi tên rẽ lớn
            Image(systemName: maneuver.type.iconName)
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(maneuver.type.isTurnLeft ? .green : (maneuver.type.isTurnRight ? .green : .blue))
                .frame(width: 54, height: 54)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(formatDistance(navigation.distanceToNextManeuver))
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("tới điểm rẽ")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Text(maneuver.instruction)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.yellow)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Góc bẻ lái
            VStack {
                Text("\(Int(abs(maneuver.turnAngleDegrees)))°")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white)
                Text(maneuver.turnAngleDegrees < 0 ? "Trái" : "Phải")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(6)
            .background(Color.white.opacity(0.15))
            .cornerRadius(8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.85))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(maneuver.isTriggered ? Color.green : Color.white.opacity(0.2), lineWidth: 2)
        )
    }
    
    /// Thanh điều khiển phía dưới đáy màn hình
    private var bottomControlBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Nút Bắt đầu / Kết thúc hành trình
                Button(action: {
                    if navigation.isNavigating {
                        navigation.stopNavigation()
                    } else {
                        showingRoutePlanner = true
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: navigation.isNavigating ? "stop.fill" : "play.fill")
                        Text(navigation.isNavigating ? "KẾT THÚC" : "CHỌN LỘ TRÌNH")
                            .font(.system(size: 15, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(navigation.isNavigating ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                
                // Nút Chế độ Tự Động (ON / OFF)
                Button(action: {
                    settings.isAutoSignalEnabled.toggle()
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: settings.isAutoSignalEnabled ? "bolt.badge.automatic.fill" : "bolt.slash.fill")
                            .font(.system(size: 18))
                        Text(settings.isAutoSignalEnabled ? "TỰ ĐỘNG: BẬT" : "TỰ ĐỘNG: TẮT")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .frame(width: 95)
                    .padding(.vertical, 10)
                    .background(settings.isAutoSignalEnabled ? Color.green.opacity(0.25) : Color.gray.opacity(0.25))
                    .foregroundColor(settings.isAutoSignalEnabled ? .green : .white)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(settings.isAutoSignalEnabled ? Color.green : Color.gray, lineWidth: 1.5)
                    )
                }
            }
            
            // Thanh công cụ phụ: Bản đồ Offline, Kiểm tra phần cứng, Cài đặt
            HStack(spacing: 12) {
                toolButton(title: "Bản đồ Offline", icon: "map.fill") { showingOfflineMaps = true }
                toolButton(title: "Test ESP32", icon: "cpu") { showingHardwareTest = true }
                toolButton(title: "Cài đặt", icon: "gearshape.fill") { showingSettings = true }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.8))
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
    
    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000.0)
        } else {
            return "\(Int(meters)) m"
        }
    }
}
