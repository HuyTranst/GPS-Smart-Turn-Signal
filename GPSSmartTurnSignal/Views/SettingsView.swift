import SwiftUI

/// Màn hình cấu hình toàn diện các thông số của GPS Smart Turn Signal
public struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var ble = BLEManager.shared
    @ObservedObject var hardware = HardwareService.shared
    @ObservedObject var controller = TurnSignalController.shared
    
    @State private var showingResetAlert = false
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            Form {
                // Section 1: Chế độ tự động
                Section(header: Text("TỰ ĐỘNG ĐIỀU KHIỂN XI NHAN")) {
                    Toggle(isOn: $settings.isAutoSignalEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tự động kích hoạt khi dẫn đường")
                                .font(.body.bold())
                            Text("Bật xi nhan trước ngã rẽ theo GPS")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Section 2: Giao tiếp phần cứng (Bluetooth / Wi-Fi)
                Section(header: Text("KẾT NỐI ESP32")) {
                    Picker("Phương thức kết nối", selection: $settings.connectionMode) {
                        ForEach(HardwareConnectionMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    if settings.connectionMode == .bluetooth {
                        HStack {
                            Text("Tên thiết bị BLE")
                            Spacer()
                            TextField("GPS_Turn_Signal", text: $settings.bleDeviceName)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.blue)
                        }
                        
                        if !ble.discoveredPeripherals.isEmpty {
                            Picker("Chọn thiết bị đã quét", selection: Binding(
                                get: { settings.savedPeripheralUUID ?? "" },
                                set: { newId in
                                    if let p = ble.discoveredPeripherals.first(where: { $0.identifier.uuidString == newId }) {
                                        ble.connect(to: p)
                                    }
                                }
                            )) {
                                Text("Chưa chọn thiết bị").tag("")
                                ForEach(ble.discoveredPeripherals, id: \.identifier) { p in
                                    Text("\(p.name ?? "ESP32") (\(p.identifier.uuidString.prefix(6))...)")
                                        .tag(p.identifier.uuidString)
                                }
                            }
                        }
                    } else {
                        HStack {
                            Text("Địa chỉ IP ESP32")
                            Spacer()
                            TextField("192.168.4.1", text: $settings.wifiHost)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .foregroundColor(.blue)
                        }
                        
                        HStack {
                            Text("Cổng (Port)")
                            Spacer()
                            TextField("80", value: $settings.wifiPort, formatter: NumberFormatter())
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                // Section 3: Cấu hình thuật toán GPS & Ngưỡng kích hoạt
                Section(header: Text("THUẬT TOÁN KÍCH HOẠT XI NHAN")) {
                    // Thời gian bật xi nhan
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Thời gian bật xi nhan")
                            Spacer()
                            Text("\(Int(settings.turnDurationSeconds)) giây")
                                .bold()
                                .foregroundColor(.blue)
                        }
                        Slider(value: $settings.turnDurationSeconds, in: 10...120, step: 5)
                            .onChange(of: settings.turnDurationSeconds) { newVal in
                                hardware.syncDurationConfig(seconds: Int(newVal))
                            }
                        Text("Mặc định 50 giây. ESP32 sẽ tự tắt độc lập khi hết thời gian.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Khoảng cách kích hoạt trước giao lộ
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Khoảng cách kích hoạt trước")
                            Spacer()
                            Text("\(Int(settings.triggerDistanceMeters)) mét")
                                .bold()
                                .foregroundColor(.blue)
                        }
                        Slider(value: $settings.triggerDistanceMeters, in: 30...200, step: 5)
                        Text("Khoảng cách tối ưu cho xe máy: 60m - 100m.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Độ nhạy góc rẽ
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Độ nhạy góc bẻ lái vào cua")
                            Spacer()
                            Text("\(Int(settings.turnSensitivityDegrees))°")
                                .bold()
                                .foregroundColor(.blue)
                        }
                        Slider(value: $settings.turnSensitivityDegrees, in: 10...50, step: 2)
                        Text("Mặc định 20°. Nhận diện ngay khi đầu xe bắt đầu bẻ lái vào cua.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Tốc độ tối thiểu
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Tốc độ GPS tối thiểu")
                            Spacer()
                            Text("\(Int(settings.minSpeedKmh)) km/h")
                                .bold()
                                .foregroundColor(.blue)
                        }
                        Slider(value: $settings.minSpeedKmh, in: 3...25, step: 1)
                        Text("Mặc định 6 km/h. Nhận diện ngay khi xe lăn bánh chậm vào ngã rẽ.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Thời gian chờ giữa 2 lần kích hoạt (Cooldown)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Thời gian chờ giữa 2 lần rẽ")
                            Spacer()
                            Text("\(Int(settings.cooldownSeconds)) giây")
                                .bold()
                                .foregroundColor(.blue)
                        }
                        Slider(value: $settings.cooldownSeconds, in: 10...60, step: 5)
                        Text("Ngăn chặn việc gửi lệnh liên tục gây quá tải relay.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Section 4: Cảnh báo âm thanh & Rung
                Section(header: Text("PHẢN HỒI")) {
                    Toggle("Âm thanh cảnh báo", isOn: $settings.isSoundAlertEnabled)
                    Toggle("Rung phản hồi xúc giác", isOn: $settings.isHapticFeedbackEnabled)
                }
                
                // Section 5: Thao tác kiểm tra nhanh relay
                Section(header: Text("THAO TÁC RELAY NHANH")) {
                    HStack {
                        Button("Test Xi Nhan Trái") {
                            controller.triggerManual(state: .left)
                        }
                        .foregroundColor(.green)
                        
                        Spacer()
                        
                        Button("Test Xi Nhan Phải") {
                            controller.triggerManual(state: .right)
                        }
                        .foregroundColor(.green)
                    }
                    
                    Button(role: .destructive, action: {
                        controller.turnOff()
                    }) {
                        HStack {
                            Spacer()
                            Text("TẮT TOÀN BỘ RELAY KHẨN CẤP")
                                .bold()
                            Spacer()
                        }
                    }
                }
                
                // Section 6: Khôi phục mặc định
                Section {
                    Button("Khôi phục cài đặt gốc") {
                        showingResetAlert = true
                    }
                    .foregroundColor(.orange)
                }
            }
            .navigationTitle("Cài Đặt Hệ Thống")
            .confirmationDialog("Khôi phục cài đặt gốc?", isPresented: $showingResetAlert, titleVisibility: .visible) {
                Button("Khôi phục mặc định", role: .destructive) {
                    settings.resetToDefaults()
                }
                Button("Hủy", role: .cancel) {}
            }
        }
    }
}
