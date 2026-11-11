# Kiến Trúc Hệ Thống & Thuật Toán GPS Smart Turn Signal

Tài liệu kỹ thuật chuyên sâu phân tích thuật toán nhận diện ngã rẽ thông minh, cơ chế chống kích hoạt sai, hệ thống khóa liên động an toàn phần cứng và cơ chế bản đồ Offline.

---

## 1. Tổng quan kiến trúc hệ thống

```
┌────────────────────────────────────────────────────────┐
│                      ỨNG DỤNG iOS                      │
│                                                        │
│  ┌──────────────────┐           ┌───────────────────┐  │
│  │ CoreLocation GPS │           │   Offline Maps    │  │
│  │ - 2m Filter      │           │ - OpenStreetMap   │  │
│  │ - Bearing Smooth │           │ - Tile Cache Disk │  │
│  └────────┬─────────┘           └─────────┬─────────┘  │
│           │                               │            │
│           ▼                               ▼            │
│  ┌──────────────────────────────────────────────────┐  │
│  │       Navigation Engine (Bộ Phân Tích Lộ Trình)   │  │
│  │  - Geodesic Distance: Xe ──► Giao Lộ              │  │
│  │  - Bearing Verification: Xe hướng về giao lộ      │  │
│  │  - Turn Angle Δθ: Loại trừ đường cong uốn lượn    │  │
│  │  - Min Speed Filter: Loại trừ rung lắc đứng yên   │  │
│  └────────────────────────┬─────────────────────────┘  │
│                           │                            │
│                           ▼                            │
│  ┌──────────────────────────────────────────────────┐  │
│  │   TurnSignalController (Điều Phối Xi Nhan)       │  │
│  │  - Dead-time 60ms chống chập                     │  │
│  │  - Cooldown timer (25s)                          │  │
│  │  - Local Countdown (50s)                         │  │
│  └────────────────────────┬─────────────────────────┘  │
│                           │                            │
│         ┌─────────────────┴─────────────────┐          │
│         ▼                                   ▼          │
│  ┌──────────────┐                   ┌──────────────┐   │
│  │  BLE Manager │                   │ WiFi Manager │   │
│  │  (GATT Write)│                   │ (REST HTTP)  │   │
│  └──────┬───────┘                   └───────┬──────┘   │
└─────────┼───────────────────────────────────┼──────────┘
          │ (Bluetooth Low Energy)            │ (Wi-Fi 2.4GHz)
          ▼                                   ▼
┌────────────────────────────────────────────────────────┐
│                   MODULE ESP32 PHẦN CỨNG               │
│                                                        │
│  - BLE Server / WebServer                              │
│  - Phần mềm Watchdog độc lập (Tự ngắt sau 50s)         │
│  - Khóa liên động cứng (Trái / Phải không thể cùng ON) │
│  - Khởi động an toàn (Boot in OFF state)               │
│                                                        │
│         ┌───────────────────┬───────────────────┐      │
│         ▼                                       ▼      │
│  [Relay Xi Nhan Trái]                 [Relay Xi Nhan Phải]
└────────────────────────────────────────────────────────┘
```

---

## 2. Thuật toán nhận diện ngã rẽ và lọc chống báo sai (False Positive Rejection)

Một lỗi kinh điển của các ứng dụng định vị đơn giản là **chỉ dựa vào thay đổi góc la bàn tức thời**. Khi xe rung lắc, người dùng chỉnh giá đỡ điện thoại, hoặc xe đi vào khúc cua mềm uốn lượn, xi nhan sẽ bị kích hoạt bừa bãi.

Dự án **GPS Smart Turn Signal** áp dụng mô hình xác thực đa tiêu chí:

### A. Góc bẻ lái thực sự của tuyến đường ($\Delta\theta$)
Góc lệch giữa đoạn đường chuẩn bị đi vào ($\theta_{out}$) và đoạn đường đang di chuyển ($\theta_{in}$):
$$\Delta\theta = (\theta_{out} - \theta_{in} + 540^\circ) \pmod{360^\circ} - 180^\circ$$

- **Nếu $|\Delta\theta| < 40^\circ$:** Phân loại là **đường cong tự nhiên**, hệ thống TUYỆT ĐỐI KHÔNG kích hoạt xi nhan.
- **Nếu $-135^\circ \le \Delta\theta \le -40^\circ$:** Xác định là **RẼ TRÁI**.
- **Nếu $+40^\circ \le \Delta\theta \le +135^\circ$:** Xác định là **RẼ PHẢI**.

### B. Khoảng cách địa lý thực tế đến tâm ngã rẽ ($D_{junction}$)
Tính theo công thức bán kính Trái Đất (Haversine / Geodesic Distance).
- Ngưỡng kích hoạt được cấu hình mặc định là $80$ mét (cho phép tùy chỉnh $30\text{m} - 200\text{m}$).
- Xi nhan chỉ được phép bật khi:
$$10\text{m} \le D_{junction} \le D_{trigger}$$

### C. Hướng đầu xe hướng về tâm giao lộ (Bearing Alignment)
Tính góc phương vị $\beta$ từ vị trí hiện tại của xe tới tọa độ tâm giao lộ:
$$|\text{Heading}_{vehicle} - \beta| \le 55^\circ$$
Đảm bảo xe đang thực sự di chuyển **tiến lại gần** nút giao, tránh trường hợp xe vừa rẽ xong hoặc đang quay đầu đi xa khỏi nút giao nhưng khoảng cách vô tình vẫn nằm trong phạm vi 80m.

### D. Tốc độ di chuyển tối thiểu ($V_{min}$)
- Yêu cầu vận tốc xe $V \ge 10\text{ km/h}$ (mặc định).
- Loại bỏ hoàn toàn tình trạng sai số GPS trôi dạt (GPS drift) khi xe đang dừng chờ đèn đỏ hoặc người dùng đang cầm điện thoại đi bộ.

### E. Tự động tắt sau khi hoàn thành khúc rẽ
Xi nhan sẽ tự tắt sớm ngay khi:
1. Khoảng cách tới ngã rẽ $D \le 12\text{m}$ (đã đến giao lộ), hoặc
2. Xe đã đi qua giao lộ và hướng đầu xe đã xoay khớp với hướng đoạn đường mới ($\pm 25^\circ$).

---

## 3. Khóa liên động an toàn (Mutual Interlocking & Dead-Time)

Cả trong ứng dụng iOS và firmware ESP32, cơ chế khóa liên động được thực thi ở mức thấp nhất:
1. **Không bao giờ cho phép 2 relay đóng đồng thời:**
   - Khi có lệnh `TURN_LEFT`, nếu relay Phải đang bật, firmware lập tức ngắt relay Phải trước.
   - Thêm thời gian chết an toàn (**Dead-Time 50ms - 60ms**) để tiếp điểm cơ khí của relay nhả hoàn toàn và dập tắt tia lửa điện hồ quang, sau đó mới đóng tiếp điểm relay Trái.
2. **Watchdog độc lập:**
   - Bộ đếm thời gian `millis()` độc lập chạy trên nhân FreeRTOS của ESP32.
   - Kể cả khi iPhone bị tắt nguồn, mất sóng Bluetooth hoặc rơi vỡ, sau tối đa 50 giây relay chắc chắn sẽ tự động ngắt về trạng thái OFF.
