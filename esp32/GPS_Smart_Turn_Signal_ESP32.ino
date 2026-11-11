/*
 * ==============================================================================
 * DỰ ÁN: GPS SMART TURN SIGNAL - FIRMWARE ESP32
 * ==============================================================================
 * Tác giả: HuyTranst
 * Chức năng: Điều khiển Relay Xi Nhan Trái/Phải tự động qua BLE và Wi-Fi
 * Tính năng an toàn:
 *  - Tự động tắt độc lập bằng Watchdog phần mềm (Mặc định 50 giây)
 *  - Khóa liên động cứng (Interlocking): Tuyệt đối KHÔNG BAO GIỜ bật đồng thời 2 bên
 *  - Khởi động an toàn: Relay luôn ở trạng thái OFF khi ESP32 khởi động/reset
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
#define PIN_RELAY_LEFT       26  // Chân điều khiển Relay xi nhan TRÁI
#define PIN_RELAY_RIGHT      27  // Chân điều khiển Relay xi nhan PHẢI
#define PIN_STATUS_LED       2   // Đèn LED báo hiệu trạng thái (Onboard LED ESP32)
#define PIN_BUZZER           25  // Còi bíp cảnh báo (tùy chọn)

// Đa số module Relay trên thị trường kích mức THẤP (Active LOW)
// Mức LOW = Relay ĐÓNG (Bật đèn), Mức HIGH = Relay NGẮT (Tắt đèn)
#define RELAY_ACTIVE_LEVEL   LOW
#define RELAY_INACTIVE_LEVEL HIGH

// ======================= CẤU HÌNH BLE GATT =======================
#define BLE_DEVICE_NAME      "GPS_Turn_Signal"
#define SERVICE_UUID         "4FAFC201-1FB5-459E-8FCC-C5C9C331914B"
#define CHARACTERISTIC_CMD   "BEB5483E-36E1-4688-B7F5-EA07361B26A8"
#define CHARACTERISTIC_STATE "1C95D5E3-D6F7-413A-AEB2-E8330D644D7B"

// ======================= CẤU HÌNH WI-FI =======================
// Mặc định phát Access Point (AP) độc lập trên xe (không cần router)
const char* AP_SSID = "GPS_Smart_Signal";
const char* AP_PASS = "12345678";
WebServer server(80);

// ======================= BIẾN TRẠNG THÁI VÀ BỘ ĐẾM =======================
bool isLeftActive = false;
bool isRightActive = false;
unsigned long autoTurnOffDurationMs = 50000; // Mặc định 50 giây tự tắt
unsigned long relayStartTimeMs = 0;

BLEServer* pServer = nullptr;
BLECharacteristic* pCmdCharacteristic = nullptr;
BLECharacteristic* pStatusCharacteristic = nullptr;
bool bleDeviceConnected = false;

// ======================= NGUYÊN MẪU HÀM =======================
void turnOffAllRelays();
void activateLeftRelay();
void activateRightRelay();
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
        }
        updateStatusBroadcast();
        server.send(200, "application/json", getStatusJson());
    } else {
        server.send(400, "text/plain", "Missing direction param (left|right|off)");
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
            Serial.printf("[HTTP CONFIG] Cập nhật tự tắt: %d giây\n", sec);
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
    isLeftActive = false;
    isRightActive = false;
    relayStartTimeMs = 0;
    Serial.println("[RELAY] Tất cả Relay: OFF");
}

/// Kích hoạt relay Trái (Đảm bảo ngắt relay Phải trước)
void activateLeftRelay() {
    // Khóa liên động: Nếu relay Phải đang bật, ngắt ngay lập tức
    if (isRightActive) {
        digitalWrite(PIN_RELAY_RIGHT, RELAY_INACTIVE_LEVEL);
        isRightActive = false;
        delay(50); // Khoảng thời gian dead-time 50ms chống hồ quang
    }

    digitalWrite(PIN_RELAY_LEFT, RELAY_ACTIVE_LEVEL);
    isLeftActive = true;
    relayStartTimeMs = millis();
    beepBuzzer(1);
    Serial.println("[RELAY] Xi nhan TRÁI: ON");
}

/// Kích hoạt relay Phải (Đảm bảo ngắt relay Trái trước)
void activateRightRelay() {
    // Khóa liên động: Nếu relay Trái đang bật, ngắt ngay lập tức
    if (isLeftActive) {
        digitalWrite(PIN_RELAY_LEFT, RELAY_INACTIVE_LEVEL);
        isLeftActive = false;
        delay(50); // Khoảng thời gian dead-time 50ms chống hồ quang
    }

    digitalWrite(PIN_RELAY_RIGHT, RELAY_ACTIVE_LEVEL);
    isRightActive = true;
    relayStartTimeMs = millis();
    beepBuzzer(2);
    Serial.println("[RELAY] Xi nhan PHẢI: ON");
}

/// Phát tiếng bíp cảnh báo (tùy chọn)
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
    Serial.println("==================================================");

    // BẢO VỆ AN TOÀN: Đặt mức điện áp INACTIVE TRƯỚC KHI pinMode OUTPUT
    // Tránh việc relay bị nháy bật một tích tắc lúc vừa cấp nguồn!
    digitalWrite(PIN_RELAY_LEFT, RELAY_INACTIVE_LEVEL);
    digitalWrite(PIN_RELAY_RIGHT, RELAY_INACTIVE_LEVEL);
    digitalWrite(PIN_STATUS_LED, LOW);
    digitalWrite(PIN_BUZZER, LOW);

    pinMode(PIN_RELAY_LEFT, OUTPUT);
    pinMode(PIN_RELAY_RIGHT, OUTPUT);
    pinMode(PIN_STATUS_LED, OUTPUT);
    pinMode(PIN_BUZZER, OUTPUT);

    // 1. Cấu hình Wi-Fi SoftAP (Tạo mạng Wi-Fi cục bộ trên xe)
    WiFi.mode(WIFI_AP);
    WiFi.softAP(AP_SSID, AP_PASS);
    Serial.print("[WIFI AP] Đã phát mạng Wi-Fi: ");
    Serial.println(AP_SSID);
    Serial.print("[WIFI AP] Địa chỉ IP ESP32: ");
    Serial.println(WiFi.softAPIP());

    // Cài đặt các tuyến REST API HTTP
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

    // Characteristic nhận lệnh từ iPhone (Write)
    pCmdCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_CMD,
        BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
    );
    pCmdCharacteristic->setCallbacks(new CommandCallbacks());

    // Characteristic phát trạng thái về iPhone (Notify/Read)
    pStatusCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_STATE,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
    );
    pStatusCharacteristic->addDescriptor(new BLE2902());

    pService->start();

    // Bắt đầu phát quảng bá BLE (Advertising)
    BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println("[BLE] GATT Server đã khởi động. Đang phát quảng bá...");
    beepBuzzer(3); // Bíp 3 tiếng báo khởi động thành công
}

// ======================= LOOP CHÍNH =======================
void loop() {
    // 1. Phục vụ các yêu cầu HTTP từ iPhone
    server.handleClient();

    // 2. BỘ ĐẾM THỜI GIAN TỰ TẮT ĐỘC LẬP (WATCHDOG TIMER PHẦN MỀM)
    // Nếu relay đang bật và thời gian vượt quá autoTurnOffDurationMs (50 giây)
    // ESP32 sẽ tự động ngắt relay ngay cả khi iPhone mất kết nối hoặc bị tắt nguồn!
    if (isLeftActive || isRightActive) {
        if (millis() - relayStartTimeMs >= autoTurnOffDurationMs) {
            Serial.printf("[WATCHDOG] Hết thời gian %lu giây. TỰ ĐỘNG TẮT RELAY!\n", autoTurnOffDurationMs / 1000UL);
            turnOffAllRelays();
            updateStatusBroadcast();
            beepBuzzer(1);
        }
    }

    // Nhấp nháy nhẹ LED trạng thái nếu không có BLE kết nối
    if (!bleDeviceConnected) {
        static unsigned long lastBlinkMs = 0;
        if (millis() - lastBlinkMs > 1000) {
            lastBlinkMs = millis();
            digitalWrite(PIN_STATUS_LED, !digitalRead(PIN_STATUS_LED));
        }
    }

    delay(5); // Cho phép CPU rảnh rỗi và xử lý tác vụ nền của ESP32 RTOS
}
