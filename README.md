# GPS Smart Turn Signal 🛵🚗💡

**GPS Smart Turn Signal** là hệ thống điều khiển đèn xi nhan tự động thông minh dành cho xe máy và ô tô, kết hợp giữa ứng dụng dẫn đường định vị GPS trên **iOS (Swift / SwiftUI)** và module vi điều khiển **ESP32** điều khiển Relay thông qua kết nối **Bluetooth Low Energy (BLE)** hoặc **Wi-Fi nội bộ**.

Hệ thống hoạt động ổn định và tin cậy ngay cả khi **màn hình điện thoại tắt hoặc ứng dụng chạy dưới nền**, đồng thời tích hợp tính năng **bản đồ OpenStreetMap Offline 100%** không phụ thuộc Internet.

---

## ✨ Tính Năng Nổi Bật

- 📍 **Định vị GPS & Dẫn đường chính xác:**
  - Nhận diện vị trí, tốc độ và góc di chuyển phương tiện thời gian thực.
  - Phân tích tuyến đường, xác định trước khoảng cách tới các ngã rẽ.
  - **Thuật toán chống báo sai độc quyền:** Không bao giờ kích hoạt xi nhan chỉ dựa vào góc la bàn tức thời hay các đoạn đường cong mềm uốn lượn ($|\Delta\theta| < 40^\circ$). Chỉ kích hoạt khi thỏa mãn đồng thời: góc rẽ giao lộ lớn, khoảng cách nằm trong ngưỡng ($30\text{m} - 200\text{m}$), đầu xe đang tiến về ngã rẽ và xe đang di chuyển ($V \ge 10\text{ km/h}$).
  - Tự động tắt xi nhan ngay khi xe hoàn thành khúc rẽ và nhập làn mới.
- 🗺️ **Bản đồ Offline hoàn toàn (Không cần Internet):**
  - Tích hợp dữ liệu bản đồ OpenStreetMap (OSM).
  - Cho phép tải và lưu trữ bản đồ các tỉnh/thành phố (Hà Nội, TP.HCM, Đà Nẵng, Hải Phòng, Cần Thơ...) trực tiếp vào bộ nhớ iPhone.
  - Giao diện quản lý dung lượng bản đồ, xem chi tiết và xóa giải phóng bộ nhớ.
- 📡 **Giao tiếp phần cứng kép (BLE & Wi-Fi):**
  - **Bluetooth Low Energy (BLE):** Tự động quét, ghép nối, ghi nhớ thiết bị và tự kết nối lại trong nền.
  - **Wi-Fi nội bộ (HTTP REST):** Kết nối vào Access Point của ESP32 (`192.168.4.1:80`), hỗ trợ kiểm tra nhịp tim (Heartbeat ping).
- 🛡️ **An toàn tuyệt đối & Khóa liên động (Interlocking):**
  - Khóa liên động cứng: Tuyệt đối KHÔNG BAO GIỜ bật đồng thời xi nhan Trái và Phải (khoảng cách an toàn dead-time 50ms chống hồ quang).
  - **Watchdog phần mềm độc lập trên ESP32:** Tự động ngắt relay sau 50 giây (hoặc thời gian tùy chỉnh) kể cả khi iPhone sập nguồn, mất kết nối hoặc thoát ứng dụng.
  - Khởi động an toàn: Relay luôn ở trạng thái OFF khi ESP32 khởi động lại.
- ⚙️ **Giao diện Dashboard HUD & Cài đặt chuyên sâu:**
  - Màn hình lái xe độ tương phản cao, hiển thị đồng hồ tốc độ lớn, la bàn, biểu tượng rẽ to bản và khoảng cách đếm ngược.
  - Đèn xi nhan nhấp nháy mô phỏng taplo xe kèm âm thanh cảnh báo và rung haptic feedback.
  - Tùy chỉnh chi tiết: Thời gian bật (mặc định 50s), khoảng cách kích hoạt, độ nhạy góc rẽ, tốc độ tối thiểu, thời gian chờ chống lặp lệnh (cooldown).
  - Các nút kiểm tra relay thủ công (Test Trái, Test Phải, Tắt khẩn cấp).
- 📱 **Hỗ trợ TrollStore (Không cần tài khoản Apple Developer):**
  - Dự án tích hợp sẵn GitHub Actions tự động build ra file IPA unsigned.
  - Cài đặt trực tiếp qua TrollStore vĩnh viễn, không bị thu hồi chứng chỉ sau 7 ngày, mở khóa đầy đủ quyền chạy ngầm (`location`, `bluetooth-central`).

---

## 📂 Cấu Trúc Dự Án

```
GPS-Smart-Turn-Signal/
├── .github/
│   └── workflows/
│       └── build-ipa.yml                 # Tự động biên dịch IPA bằng GitHub Actions (macOS-14)
├── .gitignore
├── README.md                             # Tài liệu tổng quan
├── build_ipa.sh                          # Script đóng gói IPA cục bộ trên máy Mac
├── GPS-Smart-Turn-Signal.xcodeproj/      # Cấu hình dự án Xcode
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/GPSSmartTurnSignal.xcscheme
├── GPSSmartTurnSignal/                   # Mã nguồn ứng dụng iOS (SwiftUI)
│   ├── App/
│   │   └── GPSSmartTurnSignalApp.swift   # Điểm khởi chạy ứng dụng & vòng đời
│   ├── Models/
│   │   ├── TurnCommand.swift             # Định nghĩa lệnh TURN_LEFT, TURN_RIGHT, TURN_OFF
│   │   ├── AppSettings.swift             # Quản lý toàn bộ cấu hình UserDefaults
│   │   ├── NavigationRoute.swift         # Mô hình lộ trình, điểm nút giao lộ
│   │   └── OfflineMapRegion.swift        # Quản lý gói tải bản đồ Offline
│   ├── CoreLocation/
│   │   └── LocationManager.swift         # Định vị GPS nền, lọc mịn góc di chuyển
│   ├── Navigation/
│   │   ├── NavigationEngine.swift        # Thuật toán phân tích lộ trình & kích hoạt xi nhan
│   │   └── TurnSignalController.swift    # Bộ điều phối trạng thái relay, đếm ngược tự tắt
│   ├── Hardware/
│   │   ├── BLEManager.swift              # CoreBluetooth Central, tự động kết nối lại
│   │   ├── WiFiManager.swift             # HTTP REST Client kết nối ESP32 AP
│   │   └── HardwareService.swift         # Tầng giao diện phần cứng thống nhất
│   ├── OfflineMap/
│   │   ├── OfflineMapTileManager.swift   # Quản lý tải và lưu tile OpenStreetMap
│   │   └── TileOverlayView.swift         # MKTileOverlay tùy chỉnh đọc dữ liệu Offline
│   ├── Views/
│   │   ├── MainDashboardView.swift       # Màn hình điều khiển HUD khi lái xe
│   │   ├── TurnIndicatorWidget.swift     # Widget đèn xi nhan nhấp nháy
│   │   ├── SettingsView.swift            # Màn hình cài đặt thông số chi tiết
│   │   ├── HardwareTestView.swift        # Màn hình kiểm tra phần cứng & test relay
│   │   ├── OfflineMapManagerView.swift   # Quản lý tải/xóa bản đồ các tỉnh thành
│   │   └── RoutePlannerView.swift        # Chọn lộ trình & chế độ mô phỏng GPS
│   ├── Assets.xcassets/                  # Biểu tượng và màu sắc ứng dụng
│   └── Info.plist                        # Cấu hình quyền truy cập và Background Modes
├── esp32/                                # Mã nguồn Firmware ESP32
│   ├── GPS_Smart_Turn_Signal_ESP32.ino   # Firmware Arduino hoàn chỉnh (BLE + Wi-Fi)
│   ├── platformio.ini                    # Cấu hình nạp bằng PlatformIO
│   ├── schematic_and_wiring.md           # Sơ đồ nguyên lý & hướng dẫn đấu nối 12V trên xe
│   └── README.md                         # Hướng dẫn nạp firmware cho ESP32
└── docs/
    ├── TROLLSTORE_INSTALLATION.md        # Hướng dẫn chi tiết cài file IPA bằng TrollStore
    └── SYSTEM_ARCHITECTURE.md            # Tài liệu phân tích thuật toán và an toàn điện
```

---

## 🛠️ Hướng Dẫn Cài Đặt Ứng Dụng iOS

### Phương án 1: Cài đặt IPA bằng TrollStore (Khuyên Dùng - Miễn phí 100%)

1. Vào tab **Actions** trên repository GitHub này.
2. Chọn lần chạy mới nhất của workflow `Build iOS IPA`.
3. Kéo xuống mục **Artifacts** và tải về file `GPSSmartTurnSignal-TrollStore-IPA.zip`.
4. Giải nén được file `GPSSmartTurnSignal.ipa`.
5. Chuyển file IPA sang iPhone (qua AirDrop, Telegram, Google Drive, hoặc Safari).
6. Nhấn nút Chia sẻ (Share) -> chọn **TrollStore** -> Bấm **Install**.
7. Ứng dụng sẽ được cài đặt vĩnh viễn trên iPhone, không cần tài khoản Apple Developer trả phí!

> Xem hướng dẫn chi tiết tại: [docs/TROLLSTORE_INSTALLATION.md](docs/TROLLSTORE_INSTALLATION.md).

### Phương án 2: Tự biên dịch trên máy Mac bằng Xcode

1. Clone repository về máy Mac:
   ```bash
   git clone https://github.com/HuyTranst/GPS-Smart-Turn-Signal.git
   cd GPS-Smart-Turn-Signal
   ```
2. Chạy script đóng gói tự động:
   ```bash
   chmod +x build_ipa.sh
   ./build_ipa.sh
   ```
3. File `GPSSmartTurnSignal.ipa` sẽ được tạo ngay tại thư mục gốc.

---

## ⚡ Hướng Dẫn Nạp Firmware Cho ESP32

1. Mở phần mềm **Arduino IDE** hoặc **VS Code (PlatformIO)**.
2. Mở file `esp32/GPS_Smart_Turn_Signal_ESP32.ino`.
3. Chọn board **ESP32 Dev Module** và chọn cổng COM tương ứng.
4. Nhấn **Upload** để nạp chương trình vào ESP32.
5. Sau khi nạp xong, ESP32 sẽ phát đồng thời:
   - Tín hiệu Bluetooth BLE với tên: `GPS_Turn_Signal`
   - Mạng Wi-Fi Access Point: `GPS_Smart_Signal` (Mật khẩu: `12345678`, IP: `192.168.4.1`).

> Xem chi tiết sơ đồ đấu nối dây vào hệ thống điện xe tại: [esp32/schematic_and_wiring.md](esp32/schematic_and_wiring.md).

---

## 🔌 Sơ Đồ Đấu Nối Nhanh

| Chân ESP32 | Chân Module Relay | Chức năng |
| :--- | :--- | :--- |
| **GPIO 26** | **IN1** | Relay Xi Nhan **TRÁI** |
| **GPIO 27** | **IN2** | Relay Xi Nhan **PHẢI** |
| **GPIO 2** | LED Onboard | Đèn báo kết nối |
| **5V / VIN** | OUT+ (Mạch hạ áp MP1584) | Cấp nguồn 5V DC từ ắc quy 12V qua hạ áp |
| **GND** | OUT- / Mass sườn xe | Cực âm chung |

---

## 📜 Giấy Phép & Bảo Mật

- Dự án được phát triển phục vụ an toàn giao thông và tự động hóa xe cá nhân.
- Tuyệt đối không chứa token, khóa bảo mật hay thông tin cá nhân nhạy cảm trong mã nguồn công khai.
- Tác giả: **HuyTranst**
