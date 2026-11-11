import SwiftUI

/// Màn hình kiểm tra và tương tác trực tiếp với phần cứng ESP32 & Relay
public struct HardwareTestView: View {
    @ObservedObject var hardware = HardwareService.shared
    @ObservedObject var controller = TurnSignalController.shared
    @ObservedObject var ble = BLEManager.shared
    @ObservedObject var wifi = WiFiManager.shared
    @ObservedObject var settings = AppSettings.shared
    
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            Form {
                // Section 1: Trạng thái kết nối
                Section(header: Text("TRẠNG THÁI KẾT NỐI ESP32")) {
                    HStack {
                        Text("Phương thức")
                        Spacer()
                        Text(settings.connectionMode.rawValue)
                            .foregroundColor(.blue)
                            .bold()
                    }
                    
                    HStack {
                        Text("Tình trạng")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(hardware.connectionStatus == .connected ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                            Text(hardware.connectionStatus.rawValue)
                                .bold()
                        }
                    }
                    
                    HStack {
                        Text("Chi tiết")
                        Spacer()
                        Text(hardware.statusDetail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if settings.connectionMode == .bluetooth {
                        Button(action: {
                            ble.startScanning()
                        }) {
                            Label("Quét lại Bluetooth", systemImage: "arrow.clockwise")
                        }
                    } else {
                        Button(action: {
                            wifi.checkConnection { success in
                                alertMessage = success ? "Kết nối Wi-Fi thành công (\(wifi.lastPingMs)ms)" : "Không thể kết nối đến IP: \(settings.wifiHost)"
                                showingAlert = true
                            }
                        }) {
                            Label("Kiểm tra kết nối IP Wi-Fi", systemImage: "network")
                        }
                    }
                }
                
                // Section 2: Kiểm tra Relay thủ công
                Section(header: Text("KIỂM TRA THỦ CÔNG RELAY XI NHAN")) {
                    HStack(spacing: 16) {
                        Button(action: {
                            controller.triggerManual(state: .left)
                        }) {
                            VStack(spacing: 8) {
                                Image(systemName: "arrowtriangle.backward.circle.fill")
                                    .font(.system(size: 36))
                                    .foregroundColor(.green)
                                Text("BẬT TRÁI")
                                    .font(.subheadline.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(10)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: {
                            controller.triggerManual(state: .right)
                        }) {
                            VStack(spacing: 8) {
                                Image(systemName: "arrowtriangle.forward.circle.fill")
                                    .font(.system(size: 36))
                                    .foregroundColor(.green)
                                Text("BẬT PHẢI")
                                    .font(.subheadline.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(10)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Nút kiểm tra Relay 3: Đèn số 3 Camera
                    HStack {
                        Button(action: {
                            hardware.sendCommand(.cameraWarningOn)
                        }) {
                            Label("BẬT ĐÈN SỐ 3 (CAMERA)", systemImage: "camera.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 14, weight: .bold))
                        }
                        Spacer()
                        Button("TẮT") {
                            hardware.sendCommand(.cameraWarningOff)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(6)
                    }
                    .padding(.vertical, 4)
                    
                    // Nút TẮT KHẨN CẤP
                    Button(action: {
                        controller.turnOff()
                        hardware.sendCommand(.cameraWarningOff)
                    }) {
                        HStack {
                            Spacer()
                            Label("TẮT TOÀN BỘ RELAY (KHẨN CẤP)", systemImage: "xmark.octagon.fill")
                                .font(.headline)
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                // Section 3: Widget đèn trực quan
                Section(header: Text("TÍN HIỆU ĐANG KÍCH HOẠT")) {
                    HStack {
                        Spacer()
                        TurnIndicatorWidget()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                
                // Section 4: Dữ liệu phản hồi từ ESP32
                Section(header: Text("DỮ LIỆU PHẢN HỒI TỪ ESP32")) {
                    let rawPayload = settings.connectionMode == .bluetooth ? ble.lastStatusPayload : wifi.lastStatusPayload
                    Text(rawPayload.isEmpty ? "Chưa có phản hồi mới từ ESP32" : rawPayload)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Kiểm Tra Phần Cứng")
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("Thông báo"), message: Text(alertMessage), dismissButton: .default(Text("Đóng")))
            }
        }
    }
}
