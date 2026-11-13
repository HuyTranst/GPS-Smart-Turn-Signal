import SwiftUI

/// Màn hình cấu hình toàn diện các thông số của GPS Smart Turn Signal (Lưu tự động vào bộ nhớ máy)
public struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var ble = BLEManager.shared
    @ObservedObject var hardware = HardwareService.shared
    @ObservedObject var controller = TurnSignalController.shared
    @Environment(\.presentationMode) var presentationMode
    
    @State private var showingResetAlert = false
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            Form {
                // Section 1: Chế độ tự động
                Section(header: Text("TỰ ĐỘNG ĐIỀU KHIỂN XI NHAN"),
                        footer: Text("Mọi thay đổi được tự động lưu và ghi nhớ cho các lần mở ứng dụng tiếp theo.")) {
                    Toggle(isOn: $settings.isAutoSignalEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tự động bật xi nhan khi rẽ")
                                .font(.body.bold())
                            Text("Nhận diện góc bẻ lái vào cua và bật đèn ngay lập tức")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Section 2: Cảnh báo Camera Giao Thông (Mặc định 150m)
                Section(header: HStack(spacing: 6) {
                    CCTVCameraIconView(size: 14, color: .orange)
                    Text("CẢNH BÁO CAMERA GIAO THÔNG (ĐÈN SỐ 3)")
                }) {
                    Toggle(isOn: $settings.isCameraWarningEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bật cảnh báo Camera & Đèn số 3")
                                .font(.body.bold())
                            Text("Tự động báo giọng nói và mở Relay 3 trên ESP32")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Khoảng cách cảnh báo Camera")
                            Spacer()
                            Text("\(Int(settings.cameraWarningDistanceMeters)) mét")
                                .bold()
                                .foregroundColor(.orange)
                        }
                        Slider(value: $settings.cameraWarningDistanceMeters, in: 50...1000, step: 10)
                        Text("Mặc định: 150 mét. Khi xe cách camera trong cự ly này sẽ phát cảnh báo và bật đèn số 3.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Cấu hình rung chu kỳ khi trong tầm camera (Mặc định: rung 5 lần, nghỉ 3 giây)
                    Toggle(isOn: $settings.isCameraRepeatingVibrationEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rung lặp lại khi trong vùng camera")
                                .font(.body.bold())
                            Text("Rung 5 lần dồn dập rồi nghỉ 3 giây, lặp lại cho đến khi ra khỏi vùng")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if settings.isCameraRepeatingVibrationEnabled {
                        Stepper(value: $settings.cameraVibrationPulses, in: 1...10) {
                            HStack {
                                Text("Số nhịp rung mỗi đợt")
                                Spacer()
                                Text("\(settings.cameraVibrationPulses) lần")
                                    .bold()
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Thời gian nghỉ giữa các đợt rung")
                                Spacer()
                                Text(String(format: "%.1f giây", settings.cameraVibrationPauseSeconds))
                                    .bold()
                                    .foregroundColor(.orange)
                            }
                            Slider(value: $settings.cameraVibrationPauseSeconds, in: 1.0...8.0, step: 0.5)
                            Text("Mặc định: 3.0 giây nghỉ giữa 2 đợt rung liên tiếp.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Section 3: Giao tiếp phần cứng (Bluetooth / Wi-Fi)
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
                
                // Section 4: Cấu hình thuật toán GPS & Độ trễ kích hoạt
                Section(header: Text("THÔNG SỐ KÍCH HOẠT & DELAY XI NHAN")) {
                    // Thời gian bật / delay tự tắt xi nhan (Mặc định 180 giây)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Thời gian giữ / delay tự tắt")
                            Spacer()
                            Text("\(Int(settings.turnDurationSeconds)) giây")
                                .bold()
                                .foregroundColor(.blue)
                        }
                        Slider(value: $settings.turnDurationSeconds, in: 10...300, step: 10)
                            .onChange(of: settings.turnDurationSeconds) { newVal in
                                hardware.syncDurationConfig(seconds: Int(newVal))
                            }
                        Text("Mặc định: 180 giây (3 phút). Tự động đồng bộ bộ đếm độc lập xuống ESP32.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Độ nhạy góc rẽ (Mặc định 14° để vừa quẹo là bật liền)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Độ nhạy góc bẻ lái vào cua")
                            Spacer()
                            Text("\(Int(settings.turnSensitivityDegrees))°")
                                .bold()
                                .foregroundColor(.blue)
                        }
                        Slider(value: $settings.turnSensitivityDegrees, in: 8...45, step: 1)
                        Text("Mặc định: 14°. Giá trị nhỏ giúp phát hiện ngay lập tức khi vừa nhích tay lái rẽ.")
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
                        Slider(value: $settings.minSpeedKmh, in: 1...20, step: 1)
                        Text("Mặc định: 3 km/h. Cho phép nhận diện nhạy kể cả khi bò chậm qua ngã tư.")
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
                        Slider(value: $settings.cooldownSeconds, in: 0...180, step: 1)
                        Text("Mặc định: 3 giây. Để thấp giúp qua ngã tư liên tiếp vẫn bật xi nhan liền.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Khoảng cách kích hoạt trước giao lộ (khi dẫn đường lộ trình)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Khoảng cách báo trước giao lộ")
                            Spacer()
                            Text("\(Int(settings.triggerDistanceMeters)) mét")
                                .bold()
                                .foregroundColor(.blue)
                        }
                        Slider(value: $settings.triggerDistanceMeters, in: 30...200, step: 5)
                        Text("Áp dụng khi chạy theo tuyến đường dẫn đường định sẵn.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Section 5: Cảnh báo âm thanh & Rung
                Section(header: Text("PHẢN HỒI ÂM THANH & RUNG")) {
                    Toggle("Âm thanh & Giọng nói cảnh báo", isOn: $settings.isSoundAlertEnabled)
                    Toggle("Rung phản hồi xúc giác", isOn: $settings.isHapticFeedbackEnabled)
                }
                
                // Section 6: Thao tác kiểm tra nhanh relay
                Section(header: Text("THAO TÁC RELAY NHANH")) {
                    HStack {
                        Button("Test Trái") {
                            controller.triggerManual(state: .left)
                        }
                        .foregroundColor(.green)
                        
                        Spacer()
                        
                        Button("Test Phải") {
                            controller.triggerManual(state: .right)
                        }
                        .foregroundColor(.green)
                        
                        Spacer()
                        
                        Button("Test Đèn 3") {
                            hardware.sendCommand(.cameraWarningOn)
                        }
                        .foregroundColor(.orange)
                    }
                    
                    Button(role: .destructive, action: {
                        controller.turnOff()
                        hardware.sendCommand(.cameraWarningOff)
                    }) {
                        HStack {
                            Spacer()
                            Text("TẮT TOÀN BỘ RELAY KHẨN CẤP")
                                .bold()
                            Spacer()
                        }
                    }
                }
                
                // Section 7: Khôi phục mặc định
                Section {
                    Button("Khôi phục cài đặt gốc") {
                        showingResetAlert = true
                    }
                    .foregroundColor(.orange)
                }
            }
            .navigationTitle("Cài Đặt Hệ Thống")
            .navigationBarItems(trailing: Button("Xong") {
                presentationMode.wrappedValue.dismiss()
            })
            .confirmationDialog("Khôi phục cài đặt gốc?", isPresented: $showingResetAlert, titleVisibility: .visible) {
                Button("Khôi phục mặc định", role: .destructive) {
                    settings.resetToDefaults()
                    hardware.syncDurationConfig(seconds: Int(settings.turnDurationSeconds))
                }
                Button("Hủy", role: .cancel) {}
            }
        }
    }
}
