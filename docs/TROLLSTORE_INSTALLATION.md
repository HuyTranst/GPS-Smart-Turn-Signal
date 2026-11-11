# Hướng Dẫn Cài Đặt File IPA Bằng TrollStore (Không Cần Apple Developer)

## 1. Giới thiệu về TrollStore

**TrollStore** là một tiện ích cài đặt ứng dụng (sideloading) mang tính đột phá trên iOS:
- **Hoàn toàn miễn phí:** Không cần đăng ký tài khoản Apple Developer trả phí ($99/năm).
- **Vĩnh viễn không hết hạn:** Không bị giới hạn 7 ngày như AltStore, Sideloadly hay Scarlet (không cần kết nối máy tính để gia hạn lại).
- **Không giới hạn số lượng app:** Vượt qua giới hạn 3 ứng dụng tự ký của Apple ID miễn phí.
- **Quyền hạn tối đa (Full Entitlements):** Nhờ khai thác lỗi CoreTrust trong nhân iOS, ứng dụng được cấp đầy đủ quyền chạy ngầm (`location`, `bluetooth-central`), không bị iOS tự động tắt khi màn hình khóa hoặc để trong túi quần.

### Các phiên bản iOS được TrollStore hỗ trợ:
- **TrollStore 1 & 2:** Hỗ trợ từ **iOS 14.0** đến **iOS 16.6.1**, và **iOS 17.0** (áp dụng cho tất cả các dòng chip từ A8 đến A16, M1/M2).

---

## 2. Cách tải file IPA từ GitHub Actions

Dự án này đã được tích hợp sẵn quy trình CI/CD tự động bằng GitHub Actions:

1. Truy cập vào Repository GitHub của bạn:
   `https://github.com/HuyTranst/GPS-Smart-Turn-Signal`
2. Chuyển sang tab **Actions**:
   - Chọn workflow chạy mới nhất (`Build iOS IPA`).
   - Kéo xuống mục **Artifacts** ở cuối trang.
   - Nhấn tải file `GPSSmartTurnSignal-TrollStore-IPA.zip`.
3. Giải nén file zip bạn sẽ nhận được file `GPSSmartTurnSignal.ipa`.
4. *Nếu có bản Release (gắn tag v1.0.0):* File `GPSSmartTurnSignal.ipa` được đính kèm trực tiếp tại mục **Releases**.

---

## 3. Các bước cài đặt lên iPhone

### Bước 1: Chuyển file IPA vào iPhone
Bạn có thể sử dụng bất kỳ cách nào thuận tiện:
- **AirDrop:** Gửi trực tiếp từ máy Mac sang iPhone (nhanh nhất).
- **Safari:** Truy cập GitHub bằng Safari trên iPhone và tải trực tiếp file IPA về thư mục *Tệp (Files)*.
- **Telegram / Zalo / Google Drive / iCloud Drive:** Tải file lên đám mây và mở trên iPhone.

### Bước 2: Cài đặt vào TrollStore
1. Mở ứng dụng **Tệp (Files)** trên iPhone và tìm đến file `GPSSmartTurnSignal.ipa`.
2. Chạm giữ vào file `GPSSmartTurnSignal.ipa` -> chọn **Chia sẻ (Share)**.
3. Trong danh sách ứng dụng hiện ra, chọn biểu tượng **TrollStore** (nếu không thấy, bấm *Thêm/More* rồi chọn TrollStore).
4. TrollStore sẽ mở lên và hiển thị hộp thoại xác nhận:
   > **Install GPSSmartTurnSignal?**
5. Nhấn **Install**. Ứng dụng sẽ được cài đặt và ký trực tiếp trong vòng 2 giây!
6. Biểu tượng **GPS Smart Turn Signal** sẽ xuất hiện trên Màn hình chính của iPhone.

---

## 4. Cấp quyền định vị nền khi mở ứng dụng lần đầu

Để hệ thống tự động nhận diện ngã rẽ và gửi lệnh xi nhan kể cả khi tắt màn hình:
1. Mở ứng dụng **GPS Smart Turn Signal**.
2. Khi iOS hỏi quyền truy cập Vị trí (Location):
   - Chọn **Cho phép khi dùng ứng dụng**.
   - Sau đó vào `Cài đặt iPhone` -> `GPS Signal` -> `Vị trí` -> Chọn **Luôn luôn (Always)**.
3. Cấp quyền **Bluetooth** khi ứng dụng yêu cầu để kết nối với ESP32.
