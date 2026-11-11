import Foundation
import CoreBluetooth
import Combine

/// Quản lý kết nối Bluetooth Low Energy (BLE) với module ESP32
public final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    public static let shared = BLEManager()
    
    // MARK: - GATT UUIDs
    public static let serviceUUID = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
    public static let commandCharUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A8")
    public static let statusCharUUID = CBUUID(string: "1C95D5E3-D6F7-413A-AEB2-E8330D644D7B")
    
    private var centralManager: CBCentralManager!
    @Published public var connectedPeripheral: CBPeripheral?
    @Published public var commandCharacteristic: CBCharacteristic?
    @Published public var statusCharacteristic: CBCharacteristic?
    
    @Published public var connectionStatus: ConnectionStatus = .disconnected
    @Published public var discoveredPeripherals: [CBPeripheral] = []
    @Published public var lastStatusPayload: String = ""
    @Published public var rssi: Int = 0
    
    private var isManualDisconnect = false
    private var reconnectTimer: Timer?
    
    public override init() {
        super.init()
        // Central Manager khởi tạo với RestoreIdentifierKey để hỗ trợ chạy nền trên iOS
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionShowPowerAlertKey: true,
                CBCentralManagerOptionRestoreIdentifierKey: "com.gpssmartturnsignal.ble.restore"
            ]
        )
    }
    
    // MARK: - Public Actions
    
    /// Bắt đầu quét thiết bị ESP32 xung quanh
    public func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        isManualDisconnect = false
        connectionStatus = .scanning
        discoveredPeripherals.removeAll()
        
        // Quét theo Service UUID định sẵn để nhận diện trong nền
        centralManager.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
    
    /// Dừng quét
    public func stopScanning() {
        centralManager.stopScan()
        if connectionStatus == .scanning {
            connectionStatus = .disconnected
        }
    }
    
    /// Kết nối tới một Peripheral cụ thể
    public func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectionStatus = .connecting
        connectedPeripheral = peripheral
        peripheral.delegate = self
        
        AppSettings.shared.savedPeripheralUUID = peripheral.identifier.uuidString
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
    }
    
    /// Ngắt kết nối thủ công
    public func disconnect() {
        isManualDisconnect = true
        if let p = connectedPeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        connectionStatus = .disconnected
        connectedPeripheral = nil
        commandCharacteristic = nil
        statusCharacteristic = nil
    }
    
    /// Gửi lệnh điều khiển xi nhan qua BLE
    public func sendCommand(_ command: TurnCommand, completion: ((Bool) -> Void)? = nil) {
        guard let peripheral = connectedPeripheral,
              let characteristic = commandCharacteristic,
              connectionStatus == .connected else {
            completion?(false)
            return
        }
        
        let payload = "\(command.payloadString)\n"
        if let data = payload.data(using: .utf8) {
            let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
            peripheral.writeValue(data, for: characteristic, type: writeType)
            print("BLE Sent: \(payload.trimmingCharacters(in: .whitespacesAndNewlines))")
            completion?(true)
        } else {
            completion?(false)
        }
    }
    
    /// Gửi cấu hình thời gian bật xi nhan xuống firmware ESP32
    public func sendConfigDuration(seconds: Int) {
        guard let peripheral = connectedPeripheral,
              let characteristic = commandCharacteristic else { return }
        let payload = "CONFIG:DURATION=\(seconds)\n"
        if let data = payload.data(using: .utf8) {
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("BLE: Powered ON")
            // Thử kết nối lại bằng UUID đã lưu
            if let savedUUIDStr = AppSettings.shared.savedPeripheralUUID,
               let savedUUID = UUID(uuidString: savedUUIDStr) {
                let knowns = central.retrievePeripherals(withIdentifiers: [savedUUID])
                if let known = knowns.first {
                    connect(to: known)
                    return
                }
            }
            startScanning()
        case .poweredOff:
            connectionStatus = .disconnected
            print("BLE: Powered OFF")
        case .unauthorized:
            connectionStatus = .failed
            print("BLE: Unauthorized")
        default:
            connectionStatus = .disconnected
        }
    }
    
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        // Khôi phục kết nối khi iOS đánh thức ứng dụng trong nền
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let restored = peripherals.first {
            connectedPeripheral = restored
            restored.delegate = self
            connectionStatus = .connected
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals.append(peripheral)
        }
        
        // Tự động kết nối nếu trùng tên thiết bị mong muốn hoặc UUID đã lưu
        let targetName = AppSettings.shared.bleDeviceName
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        
        if advName.contains(targetName) || peripheral.identifier.uuidString == AppSettings.shared.savedPeripheralUUID {
            connect(to: peripheral)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionStatus = .connected
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
        peripheral.readRSSI()
        print("BLE: Connected to \(peripheral.name ?? "ESP32")")
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionStatus = .failed
        print("BLE: Failed to connect - \(error?.localizedDescription ?? "")")
        scheduleReconnect()
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionStatus = .disconnected
        commandCharacteristic = nil
        statusCharacteristic = nil
        print("BLE: Disconnected from \(peripheral.name ?? "ESP32")")
        
        if !isManualDisconnect {
            scheduleReconnect()
        }
    }
    
    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.startScanning()
        }
    }
    
    // MARK: - CBPeripheralDelegate
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.commandCharUUID, Self.statusCharUUID], for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            if char.uuid == Self.commandCharUUID {
                commandCharacteristic = char
                print("BLE: Command Characteristic ready")
            } else if char.uuid == Self.statusCharUUID {
                statusCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
                print("BLE: Status Characteristic ready (Notifying)")
            }
        }
        
        // Gửi ngay cấu hình thời gian bật xi nhan
        sendConfigDuration(seconds: Int(AppSettings.shared.turnDurationSeconds))
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == Self.statusCharUUID, let data = characteristic.value,
           let text = String(data: data, encoding: .utf8) {
            lastStatusPayload = text.trimmingCharacters(in: .whitespacesAndNewlines)
            print("BLE Status from ESP32: \(lastStatusPayload)")
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        self.rssi = RSSI.intValue
    }
}
