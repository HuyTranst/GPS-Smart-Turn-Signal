import SwiftUI

@main
struct GPSSmartTurnSignalApp: App {
    // Khởi tạo các dịch vụ toàn cục
    @StateObject private var settings = AppSettings.shared
    @StateObject private var hardware = HardwareService.shared
    @StateObject private var location = LocationManager.shared
    @StateObject private var navigation = NavigationEngine.shared
    @StateObject private var controller = TurnSignalController.shared
    
    var body: some Scene {
        WindowGroup {
            MainDashboardView()
                .preferredColorScheme(.dark) // Giao diện tối ưu tương phản cao khi lái xe
                .onAppear {
                    location.requestPermissions()
                    hardware.configureActiveMode()
                }
        }
    }
}
