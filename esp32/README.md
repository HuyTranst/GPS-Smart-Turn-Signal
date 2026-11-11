# Hướng Dẫn Biên Dịch & Nạp Firmware ESP32

## 1. Nạp bằng Arduino IDE

1. **Cài đặt Board ESP32:**
   - Mở Arduino IDE -> `File` -> `Preferences`.
   - Tại mục *Additional Boards Manager URLs*, thêm URL:
     `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
   - Vào `Tools` -> `Board` -> `Boards Manager...`, tìm kiếm `esp32` của Espressif Systems và nhấn **Install**.

2. **Cấu hình Board:**
   - `Tools` -> `Board` -> `ESP32 Arduino` -> chọn **ESP32 Dev Module** (hoặc board tương ứng).
   - `Upload Speed`: **921600** (hoặc 115200 nếu cáp kém).
   - `Flash Frequency`: **80MHz**.
   - `Partition Scheme`: **Minimal SPIFFS (1.9MB APP with OTA/190KB SPIFFS)**.
   - Chọn đúng cổng **Port** COM của ESP32.

3. **Nạp Firmware:**
   - Mở file `GPS_Smart_Turn_Signal_ESP32.ino`.
   - Nhấn nút **Upload** (Mũi tên sang phải).

---

## 2. Nạp bằng PlatformIO (VS Code)

1. Mở thư mục `esp32` bằng VS Code đã cài extension PlatformIO.
2. Cắm cáp ESP32 vào máy tính.
3. Nhấn biểu tượng PlatformIO ở thanh bên trái -> `General` -> `Upload and Monitor`.

---

## 3. Kiểm tra hoạt động ban đầu

1. Mở **Serial Monitor** với tốc độ `115200 baud`.
2. Nhấn nút Reset (EN) trên ESP32, màn hình Serial sẽ hiển thị:
   ```
   ==================================================
     KHỞI ĐỘNG HỆ THỐNG GPS SMART TURN SIGNAL ESP32
   ==================================================
   [RELAY] Tất cả Relay: OFF
   [WIFI AP] Đã phát mạng Wi-Fi: GPS_Smart_Signal
   [WIFI AP] Địa chỉ IP ESP32: 192.168.4.1
   [HTTP] WebServer HTTP sẵn sàng trên cổng 80
   [BLE] GATT Server đã khởi động. Đang phát quảng bá...
   ```
3. Mở ứng dụng **GPS Smart Turn Signal** trên iPhone:
   - Nếu chọn **Bluetooth**: Ứng dụng sẽ tự động dò và ghép nối với `GPS_Turn_Signal`. Đèn LED xanh trên ESP32 sẽ sáng liên tục.
   - Nếu chọn **Wi-Fi**: Vào Cài đặt Wi-Fi trên iPhone kết nối vào mạng `GPS_Smart_Signal` (Mật khẩu: `12345678`).
