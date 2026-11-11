/*
 * ==============================================================================
 * DỰ ÁN: GPS SMART TURN SIGNAL - FIRMWARE ESP32 (V1.1 - THÊM ĐÈN SỐ 3 CAMERA)
 * ==============================================================================
 * Tác giả: HuyTranst
 * Chức năng:
 *  - Relay 1: Xi nhan TRÁI (Kích hoạt khi sắp rẽ trái)
 *  - Relay 2: Xi nhan PHẢI (Kích hoạt khi sắp rẽ phải)
 *  - Relay 3: Đèn số 3 (Kích hoạt khi cách Camera giao thông 500m)
 * Tính năng an toàn:
 *  - Tự động tắt độc lập bằng Watchdog phần mềm (Mặc định 50 giây cho xi nhan, 60 giây cho camera)
 *  - Khóa liên động cứng: Tuyệt đối KHÔNG BAO GIỜ bật đồng thời xi nhan trái & phải
 *  - Khởi động an toàn: Toàn bộ Relay luôn ở trạng thái OFF khi ESP32 khởi động/reset
 *  - Hỗ trợ đồng thời Bluetooth Low Energy (BLE) và WebServer HTTP nội bộ
 * ==============================================================================
 */

#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ======================= CẤU HÌNH PHẦN CỨNG GPIO =======================
#define PIN_RELAY_LEFT       26  // Relay 1: Xi nhan TRÁI
#define PIN_RELAY_RIGHT      27  // Relay 2: Xi nhan PHẢI
#define PIN_RELAY_CAMERA     14  // Relay 3: ĐÈN SỐ 3 - Cảnh báo Camera giao thông
#define PIN_STATUS_LED       2   // Đèn LED báo hiệu trạng thái (Onboard LED ESP32)
#define PIN_BUZZER           25  // Còi bíp cảnh báo

// Đa số module Relay trên thị trường kích mức THẤP (Active LOW)
#define RELAY_ACTIVE_LEVEL   LOW
#define RELAY_INACTIVE_LEVEL HIGH

// ======================= CẤU HÌNH BLE GATT =======================
#define BLE_DEVICE_NAME      "GPS_Turn_Signal"
#define SERVICE_UUID         "4FAFC201-1FB5-459E-8FCC-C5C9C331914B"
#define CHARACTERISTIC_CMD   "BEB5483E-36E1-4688-B7F5-EA07361B26A8"
#define CHARACTERISTIC_STATE "1C95D5E3-D6F7-413A-AEB2-E8330D644D7B"

// ======================= CẤU HÌNH WI-FI =======================
const char* AP_SSID = "GPS_Smart_Signal";
const char* AP_PASS = "12345678";
WebServer server(80);

// ======================= BIẾN TRẠNG THÁI VÀ BỘ ĐẾM =======================
bool isLeftActive = false;
bool isRightActive = false;
bool isCameraActive = false;

unsigned long autoTurnOffDurationMs = 50000;    // 50 giây tự tắt xi nhan
unsigned long autoCameraOffDurationMs = 60000;   // 60 giây tự tắt đèn camera bảo vệ ắc quy
unsigned long relayStartTimeMs = 0;
unsigned long cameraStartTimeMs = 0;

BLEServer* pServer = nullptr;
BLECharacteristic* pCmdCharacteristic = nullptr;
BLECharacteristic* pStatusCharacteristic = nullptr;
bool bleDeviceConnected = false;

// ======================= NGUYÊN MẪU HÀM =======================
void turnOffAllRelays();
void activateLeftRelay();
void activateRightRelay();
void activateCameraRelay();
void deactivateCameraRelay();
void updateStatusBroadcast();
String getStatusJson();
void beepBuzzer(int count);

// ======================= BLE CALLBACKS =======================
class MyServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) override {
        bleDeviceConnected = true;
        digitalWrite(PIN_STATUS_LED, HIGH);
        Serial.println("[BLE] iPhone đã kết nối thành công!");
    }

    void onDisconnect(BLEServer* pServer) override {
        bleDeviceConnected = false;
        digitalWrite(PIN_STATUS_LED, LOW);
        Serial.println("[BLE] iPhone đã ngắt kết nối. Đang phát lại quảng bá...");
        BLEDevice::startAdvertising();
    }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pCharacteristic) override {
        String value = pCharacteristic->getValue().c_str();
        value.trim();
        if (value.length() == 0) return;

        Serial.print("[BLE CMD] Nhận lệnh: ");
        Serial.println(value);

        if (value.indexOf("TURN_LEFT") >= 0) {
            activateLeftRelay();
        } else if (value.indexOf("TURN_RIGHT") >= 0) {
            activateRightRelay();
        } else if (value.indexOf("TURN_OFF") >= 0) {
            turnOffAllRelays();
        } else if (value.indexOf("CAMERA_ON") >= 0 || value.indexOf("CAM_ON") >= 0) {
            activateCameraRelay();
        } else if (value.indexOf("CAMERA_OFF") >= 0 || value.indexOf("CAM_OFF") >= 0) {
            deactivateCameraRelay();
        } else if (value.indexOf("CONFIG:DURATION=") >= 0) {
            int idx = value.indexOf("=") + 1;
            int sec = value.substring(idx).toInt();
            if (sec >= 5 && sec <= 300) {
                autoTurnOffDurationMs = sec * 1000UL;
                Serial.printf("[CONFIG] Đã cập nhật thời gian tự tắt: %d giây\n", sec);
            }
        }
        updateStatusBroadcast();
    }
};

// ======================= HTTP REST API HANDLERS =======================
void handleTurn() {
    if (server.hasArg("direction")) {
        String dir = server.arg("direction");
        dir.toLowerCase();
        if (dir == "left") {
            activateLeftRelay();
        } else if (dir == "right") {
            activateRightRelay();
        } else if (dir == "off") {
            turnOffAllRelays();
        } else if (dir == "camera_on" || dir == "cam_on") {
            activateCameraRelay();
        } else if (dir == "camera_off" || dir == "cam_off") {
            deactivateCameraRelay();
        }
        updateStatusBroadcast();
        server.send(200, "application/json", getStatusJson());
    } else {
        server.send(400, "text/plain", "Missing direction param (left|right|off|camera_on|camera_off)");
    }
}

void handleStatus() {
    server.send(200, "application/json", getStatusJson());
}

void handleConfig() {
    if (server.hasArg("duration")) {
        int sec = server.arg("duration").toInt();
        if (sec >= 5 && sec <= 300) {
            autoTurnOffDurationMs = sec * 1000UL;
            Serial.printf("[HTTP CONFIG] Cập nhật tự tắt xi nhan: %d giây\n", sec);
            server.send(200, "application/json", "{\"status\":\"ok\",\"duration_sec\":" + String(sec) + "}");
            return;
        }
    }
    server.send(400, "text/plain", "Invalid duration");
}

// ======================= LOGIC ĐIỀU KHIỂN RELAY AN TOÀN =======================

/// Tắt toàn bộ relay về trạng thái an toàn
void turnOffAllRelays() {
    digitalWrite(PIN_RELAY_LEFT, RELAY_INACTIVE_LEVEL);
    digitalWrite(PIN_RELAY_RIGHT, RELAY_INACTIVE_LEVEL);
    digitalWrite(PIN_RELAY_CAMERA, RELAY_INACTIVE_LEVEL);
    isLeftActive = false;
    isRightActive = false;
    isCameraActive = false;
    relayStartTimeMs = 0;
    cameraStartTimeMs = 0;
    Serial.println("[RELAY] Tất cả Relay (Trái, Phải, Đèn số 3 Camera): OFF");
}

/// Kích hoạt relay Trái (Đảm bảo ngắt relay Phải trước)
void activateLeftRelay() {
    if (isRightActive) {
        digitalWrite(PIN_RELAY_RIGHT, RELAY_INACTIVE_LEVEL);
        isRightActive = false;
        delay(50);
    }
    digitalWrite(PIN_RELAY_LEFT, RELAY_ACTIVE_LEVEL);
    isLeftActive = true;
    relayStartTimeMs = millis();
    beepBuzzer(1);
    Serial.println("[RELAY] Xi nhan TRÁI: ON");
}

/// Kích hoạt relay Phải (Đảm bảo ngắt relay Trái trước)
void activateRightRelay() {
    if (isLeftActive) {
        digitalWrite(PIN_RELAY_LEFT, RELAY_INACTIVE_LEVEL);
        isLeftActive = false;
        delay(50);
    }
    digitalWrite(PIN_RELAY_RIGHT, RELAY_ACTIVE_LEVEL);
    isRightActive = true;
    relayStartTimeMs = millis();
    beepBuzzer(2);
    Serial.println("[RELAY] Xi nhan PHẢI: ON");
}

/// Kích hoạt relay 3: BẬT ĐÈN SỐ 3 CẢNH BÁO CAMERA GIAO THÔNG (500M)
void activateCameraRelay() {
    digitalWrite(PIN_RELAY_CAMERA, RELAY_ACTIVE_LEVEL);
    isCameraActive = true;
    cameraStartTimeMs = millis();
    beepBuzzer(3); // Bíp 3 tiếng dồn dập cảnh báo có camera
    Serial.println("[RELAY] ĐÈN SỐ 3 (CAMERA GIAO THÔNG 500M): ON");
}

/// Tắt relay 3: TẮT ĐÈN SỐ 3 CẢNH BÁO CAMERA
void deactivateCameraRelay() {
    digitalWrite(PIN_RELAY_CAMERA, RELAY_INACTIVE_LEVEL);
    isCameraActive = false;
    cameraStartTimeMs = 0;
    Serial.println("[RELAY] ĐÈN SỐ 3 (CAMERA GIAO THÔNG): OFF");
}

/// Phát tiếng bíp cảnh báo
void beepBuzzer(int count) {
    for (int i = 0; i < count; i++) {
        digitalWrite(PIN_BUZZER, HIGH);
        delay(35);
        digitalWrite(PIN_BUZZER, LOW);
        if (i < count - 1) delay(40);
    }
}

/// Tạo chuỗi JSON báo cáo trạng thái hệ thống
String getStatusJson() {
    int remainingSec = 0;
    if (isLeftActive || isRightActive) {
        unsigned long elapsed = millis() - relayStartTimeMs;
        if (elapsed < autoTurnOffDurationMs) {
            remainingSec = (autoTurnOffDurationMs - elapsed) / 1000UL;
        }
    }

    String json = "{";
    json += "\"left\":" + String(isLeftActive ? "true" : "false") + ",";
    json += "\"right\":" + String(isRightActive ? "true" : "false") + ",";
    json += "\"camera\":" + String(isCameraActive ? "true" : "false") + ",";
    json += "\"remaining_sec\":" + String(remainingSec) + ",";
    json += "\"duration_sec\":" + String(autoTurnOffDurationMs / 1000UL) + ",";
    json += "\"ble_connected\":" + String(bleDeviceConnected ? "true" : "false");
    json += "}";
    return json;
}

/// Gửi thông báo trạng thái cập nhật qua BLE Notify
void updateStatusBroadcast() {
    if (bleDeviceConnected && pStatusCharacteristic != nullptr) {
        String status = getStatusJson();
        pStatusCharacteristic->setValue(status.c_str());
        pStatusCharacteristic->notify();
    }
}

// ======================= SETUP =======================
void setup() {
    Serial.begin(115200);
    delay(200);
    Serial.println("\n\n==================================================");
    Serial.println("  KHỞI ĐỘNG HỆ THỐNG GPS SMART TURN SIGNAL ESP32");
    Serial.println("  HỖ TRỢ RELAY 1 (TRÁI), RELAY 2 (PHẢI), RELAY 3 (CAMERA)");
    Serial.println("==================================================");

    // BẢO VỆ AN TOÀN: Đặt mức điện áp INACTIVE TRƯỚC KHI pinMode OUTPUT
    digitalWrite(PIN_RELAY_LEFT, RELAY_INACTIVE_LEVEL);
    digitalWrite(PIN_RELAY_RIGHT, RELAY_INACTIVE_LEVEL);
    digitalWrite(PIN_RELAY_CAMERA, RELAY_INACTIVE_LEVEL);
    digitalWrite(PIN_STATUS_LED, LOW);
    digitalWrite(PIN_BUZZER, LOW);

    pinMode(PIN_RELAY_LEFT, OUTPUT);
    pinMode(PIN_RELAY_RIGHT, OUTPUT);
    pinMode(PIN_RELAY_CAMERA, OUTPUT);
    pinMode(PIN_STATUS_LED, OUTPUT);
    pinMode(PIN_BUZZER, OUTPUT);

    // 1. Cấu hình Wi-Fi SoftAP
    WiFi.mode(WIFI_AP);
    WiFi.softAP(AP_SSID, AP_PASS);
    Serial.print("[WIFI AP] Đã phát mạng Wi-Fi: ");
    Serial.println(AP_SSID);
    Serial.print("[WIFI AP] Địa chỉ IP ESP32: ");
    Serial.println(WiFi.softAPIP());

    server.on("/api/turn", HTTP_GET, handleTurn);
    server.on("/api/status", HTTP_GET, handleStatus);
    server.on("/api/config", HTTP_POST, handleConfig);
    server.begin();
    Serial.println("[HTTP] WebServer HTTP sẵn sàng trên cổng 80");

    // 2. Cấu hình Bluetooth Low Energy (BLE)
    BLEDevice::init(BLE_DEVICE_NAME);
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());

    BLEService* pService = pServer->createService(SERVICE_UUID);

    pCmdCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_CMD,
        BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
    );
    pCmdCharacteristic->setCallbacks(new CommandCallbacks());

    pStatusCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_STATE,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
    );
    pStatusCharacteristic->addDescriptor(new BLE2902());

    pService->start();

    BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println("[BLE] GATT Server đã khởi động. Đang phát quảng bá...");
    beepBuzzer(3);
}

// ======================= LOOP CHÍNH =======================
void loop() {
    // 1. Phục vụ yêu cầu HTTP từ iPhone
    server.handleClient();

    // 2. WATCHDOG TIMER TỰ TẮT XI NHAN (Mặc định 50 giây)
    if (isLeftActive || isRightActive) {
        if (millis() - relayStartTimeMs >= autoTurnOffDurationMs) {
            Serial.printf("[WATCHDOG] Hết thời gian xi nhan %lu giây. TỰ ĐỘNG TẮT!\n", autoTurnOffDurationMs / 1000UL);
            digitalWrite(PIN_RELAY_LEFT, RELAY_INACTIVE_LEVEL);
            digitalWrite(PIN_RELAY_RIGHT, RELAY_INACTIVE_LEVEL);
            isLeftActive = false;
            isRightActive = false;
            relayStartTimeMs = 0;
            updateStatusBroadcast();
            beepBuzzer(1);
        }
    }

    // 3. WATCHDOG TIMER TỰ TẮT ĐÈN SỐ 3 CAMERA (Mặc định 60 giây nếu app mất kết nối)
    if (isCameraActive) {
        if (millis() - cameraStartTimeMs >= autoCameraOffDurationMs) {
            Serial.println("[WATCHDOG] Quá 60 giây không có lệnh mới. TỰ ĐỘNG TẮT ĐÈN CAMERA SỐ 3!");
            deactivateCameraRelay();
            updateStatusBroadcast();
        }
    }

    // Nhấp nháy LED trạng thái nếu chưa kết nối BLE
    if (!bleDeviceConnected) {
        static unsigned long lastBlinkMs = 0;
        if (millis() - lastBlinkMs > 1000) {
            lastBlinkMs = millis();
            digitalWrite(PIN_STATUS_LED, !digitalRead(PIN_STATUS_LED));
        }
    }

    delay(5);
}
