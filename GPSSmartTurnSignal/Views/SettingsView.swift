import SwiftUI

/// Màn hình cấu hình toàn diện các thông số của GPS Smart Turn Signal (Lưu tự động vào bộ nhớ máy)
public struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var ble = BLEManager.shared
    @ObservedObject var hardware = HardwareService.shared
    @ObservedObject var controller = TurnSignalController.shared
    @Environment(\.presentationMode) var presentationMode
    
    @State private var showingResetAlert = false
    @State private var showingCameraList = false
    @State private var showingOfflineMaps = false
    @State private var showingHardwareTest = false
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            Form {
                // Section 0: Tính năng & Tiện ích (Camera, Bản đồ, Test ESP32)
                Section(header: Text("TÍNH NĂNG & TIỆN ÍCH")) {
                    Button(action: { showingCameraList = true }) {
                        HStack(spacing: 12) {
                            CCTVCameraIconView(size: 20, color: .orange)
                                .frame(width: 32, height: 32)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Camera Giao Thông & Phạt Nguội")
                                    .font(.body.bold())
                                    .foregroundColor(.primary)
                                Text("Xem danh mục camera offline Cần Thơ, Sóc Trăng, Toàn quốc")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    
                    Button(action: { showingOfflineMaps = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.blue)
                                .frame(width: 32, height: 32)
                                .background(Color.blue.opacity(0.15))
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bản Đồ Ngoại Tuyến (Offline Maps)")
                                    .font(.body.bold())
                                    .foregroundColor(.primary)
                                Text("Quản lý và tải bản đồ dùng 100% không cần mạng")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    
                    Button(action: { showingHardwareTest = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "cpu")
                                .font(.system(size: 18))
                                .foregroundColor(.purple)
                                .frame(width: 32, height: 32)
                                .background(Color.purple.opacity(0.15))
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Kiểm Tra Phần Cứng ESP32")
                                    .font(.body.bold())
                                    .foregroundColor(.primary)
                                Text("Quét thiết bị Bluetooth BLE, cấu hình Wi-Fi")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                
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
                            Text("Rung dồn dập rồi tạm nghỉ, lặp lại liên tục cho đến khi ra khỏi vùng")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Stepper(value: $settings.cameraVibrationPulses, in: 1...10) {
                        HStack {
                            Text("Số nhịp rung mỗi đợt")
                                .font(.body.bold())
                            Spacer()
                            Text("\(settings.cameraVibrationPulses) lần")
                                .bold()
                                .foregroundColor(.orange)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Thời gian nghỉ giữa các đợt rung")
                                .font(.body.bold())
                            Spacer()
                            Text(String(format: "%.1f giây", settings.cameraVibrationPauseSeconds))
                                .bold()
                                .foregroundColor(.orange)
                        }
                        Slider(value: $settings.cameraVibrationPauseSeconds, in: 1.0...8.0, step: 0.5)
                        Text("Mặc định: Rung 5 lần dồn dập, nghỉ 3.0 giây, lặp lại liên tục.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Nút bấm thử rung trực tiếp
                    Button(action: {
                        TrafficCameraManager.shared.triggerTestCameraVibration()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .foregroundColor(.orange)
                            Text("Bấm Thử Nghiệm Nhịp Rung (\(settings.cameraVibrationPulses) lần)")
                                .font(.subheadline.bold())
                                .foregroundColor(.orange)
                        }
                        .padding(.vertical, 2)
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
                
                // Section 6: Kiểm tra thử xi nhan & Relay (Test Relay)
                Section(header: Text("KIỂM TRA THỬ XI NHAN (TEST RELAY)")) {
                    VStack(spacing: 12) {
                        // Trạng thái hiện tại
                        HStack {
                            Text("Trạng thái relay:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            if controller.currentState == .left {
                                Text("ĐANG BẬT XI NHAN TRÁI (\(controller.remainingSeconds)s)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.green)
                            } else if controller.currentState == .right {
                                Text("ĐANG BẬT XI NHAN PHẢI (\(controller.remainingSeconds)s)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.green)
                            } else {
                                Text("ĐÃ TẮT")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // 2 button lớn test RẼ TRÁI và RẼ PHẢI
                        HStack(spacing: 12) {
                            Button(action: {
                                if controller.currentState == .left {
                                    controller.turnOff()
                                } else {
                                    controller.triggerManual(state: .left)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrowtriangle.backward.fill")
                                    Text("RẼ TRÁI")
                                        .font(.headline.bold())
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(controller.currentState == .left ? Color.green : Color.blue)
                                .cornerRadius(12)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            
                            Button(action: {
                                if controller.currentState == .right {
                                    controller.turnOff()
                                } else {
                                    controller.triggerManual(state: .right)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Text("RẼ PHẢI")
                                        .font(.headline.bold())
                                    Image(systemName: "arrowtriangle.forward.fill")
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(controller.currentState == .right ? Color.green : Color.blue)
                                .cornerRadius(12)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        
                        HStack(spacing: 12) {
                            // Test mở đèn 3
                            Button(action: {
                                hardware.sendCommand(.cameraWarningOn)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "lightbulb.fill")
                                    Text("Mở Đèn 3 (Cam)")
                                        .font(.subheadline.bold())
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.orange)
                                .cornerRadius(10)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            
                            // Tắt toàn bộ relay
                            Button(action: {
                                controller.turnOff()
                                hardware.sendCommand(.cameraWarningOff)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle.fill")
                                    Text("Tắt Hết Relay")
                                        .font(.subheadline.bold())
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.red)
                                .cornerRadius(10)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
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
            .sheet(isPresented: $showingCameraList) { TrafficCameraListView() }
            .sheet(isPresented: $showingOfflineMaps) { OfflineMapManagerView() }
            .sheet(isPresented: $showingHardwareTest) { HardwareTestView() }
        }
    }
}
