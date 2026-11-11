# Sơ Đồ Nguyên Lý Và Hướng Dẫn Đấu Nối Phần Cứng ESP32

Tài liệu hướng dẫn chi tiết cách đấu nối mạch điều khiển xi nhan thông minh sử dụng **ESP32** và **Module 2 Relay cách ly quang** trên xe máy hoặc ô tô (nguồn điện 12V DC).

---

## 1. Sơ đồ kết nối chân GPIO ESP32

| Chân ESP32 | Linh kiện kết nối | Chức năng | Ghi chú |
| :--- | :--- | :--- | :--- |
| **GPIO 26** | **IN1** (Module Relay) | Điều khiển xi nhan **TRÁI** | Mức LOW = Bật, HIGH = Tắt |
| **GPIO 27** | **IN2** (Module Relay) | Điều khiển xi nhan **PHẢI** | Mức LOW = Bật, HIGH = Tắt |
| **GPIO 2** | **LED Onboard** | Đèn báo trạng thái kết nối | Sáng khi BLE đã kết nối |
| **GPIO 25** | **Còi Buzzer 5V** (Tùy chọn) | Bíp báo động khi chuyển hướng | Cực dương còi (+), cực âm GND |
| **5V / VIN** | **OUT+** của Mạch hạ áp 5V | Nguồn nuôi 5V DC cho ESP32 | Tuyệt đối không cấp quá 5.5V |
| **GND** | **OUT-** / Mass sườn xe | Cực âm chung (Ground) | Đấu chung Mass toàn hệ thống |

---

## 2. Sơ đồ khối tổng thể (Block Diagram)

```
[Ắc Quy Xe 12V] (Sau ổ khóa ACC)
       │
       ▼ (12V DC qua cầu chì 2A)
┌─────────────────────────────────┐
│ Mạch Hạ Áp DC-DC Buck (MP1584)  │
│ IN: 12V-14V  ───►  OUT: 5.0V    │
└────────────────┬────────────────┘
                 │
      ┌──────────┴──────────┐
      ▼ (5V DC)             ▼ (5V DC)
┌──────────────┐      ┌─────────────────────────┐
│ ESP32 DevKit │◄────►│ Module 2 Relay (5V Opto)│
│ (BLE / Wi-Fi)│GPIO26│ - IN1: Relay Trái       │
│              │GPIO27│ - IN2: Relay Phải       │
└──────────────┘      └────────────┬────────────┘
                                   │
               ┌───────────────────┴───────────────────┐
               ▼                                       ▼
  [Tiếp điểm Relay Trái]                 [Tiếp điểm Relay Phải]
(Nối song song công tắc Trái)          (Nối song song công tắc Phải)
               │                                       │
               ▼                                       ▼
    Đèn xi nhan TRÁI xe                     Đèn xi nhan PHẢI xe
```

---

## 3. Cách đấu nối tiếp điểm Relay vào hệ thống điện xe

Đa số xe máy (Honda, Yamaha, Suzuki, Piaggio...) sử dụng cục chớp xi nhan (Flasher Relay) 2 chân (B - L) hoặc 3 chân:
- **Chân B (Battery/Power):** Nguồn 12V sau ổ khóa.
- **Chân L (Load):** Nguồn xung nhấp nháy 12V đi lên công tắc xi nhan tay lái.
- **Công tắc xi nhan tay lái:** Gạt trái cấp điện ra bóng đèn trái, gạt phải cấp điện ra bóng đèn phải.

### Phương pháp đấu song song (Khuyên dùng - Giữ nguyên công tắc zin của xe):
1. **Dây cấp vào Relay (COM):**
   - Nối chân **COM1** (Relay 1) và **COM2** (Relay 2) lại với nhau.
   - Nối cụm này vào **Dây L (nguồn xung sau cục chớp)** hoặc dây giữa của công tắc xi nhan trên ghi-đông.
2. **Dây ra đèn Trái:**
   - Nối chân **NO1** (Normally Open - Thường mở của Relay 1) vào dây dương đèn xi nhan Trái.
3. **Dây ra đèn Phải:**
   - Nối chân **NO2** (Normally Open - Thường mở của Relay 2) vào dây dương đèn xi nhan Phải.

> **Ưu điểm vượt trội:**
> - Bạn vẫn gạt công tắc xi nhan zin trên xe hoàn toàn bình thường.
> - Khi điện thoại ra lệnh rẽ, relay đóng lại tương đương như việc bạn gạt công tắc, đèn sẽ tự động chớp theo đúng nhịp chớp zin của xe.
> - Khi hết 50 giây hoặc đi qua ngã rẽ, relay nhả ra và đèn xi nhan tắt.

---

## 4. Các lưu ý quan trọng về an toàn điện trên xe

1. **Bảo vệ chống sốc điện (Spike Protection):**
   - Máy phát điện (cuộn lửa/mâm lửa) của xe máy khi vặn ga cao có thể phát sinh điện áp gai lên đến 40V-60V.
   - **Bắt buộc** sử dụng mạch hạ áp Buck DC-DC chất lượng (như MP1584, LM2596 hoặc module sạc xe hơi xịn) có tích hợp tụ lọc lớn và đi-ốt chống ngược chiều.
2. **Cầu chì bảo vệ:**
   - Đặt 1 cầu chì ống **2A hoặc 3A** ngay sau dây dương (+) lấy từ ổ khóa ACC trước khi cấp vào mạch hạ áp.
3. **Cách ly quang (Optocoupler):**
   - Giữ nguyên chân nối jumper `JD-VCC` trên module relay để bảo vệ vi điều khiển ESP32 không bị nhiễu do dòng cảm ứng của cuộn hút relay gây ra hiện tượng treo/reset vi điều khiển.
