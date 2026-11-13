import Foundation
import Combine
import AudioToolbox
import UIKit
import AVFoundation

/// Bộ điều phối trạng thái đèn xi nhan, chống dội lệnh và quản lý bộ đếm thời gian
public final class TurnSignalController: ObservableObject {
    public static let shared = TurnSignalController()
    
    // MARK: - Published Properties
    @Published public var currentState: TurnSignalState = .off
    @Published public var remainingSeconds: Int = 0
    @Published public var lastTriggerTime: Date = Date.distantPast
    @Published public var isBlinkingActive: Bool = false
    
    private var turnDeadline: Date?
    private var autoOffTimer: Timer?
    private var blinkTimer: Timer?
    private let hardwareService = HardwareService.shared
    private let settings = AppSettings.shared
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    private init() {}
    
    // MARK: - Public Triggers
    
    /// Kích hoạt xi nhan từ thuật toán dẫn đường GPS
    public func triggerNavigationTurn(isLeft: Bool, distanceToJunction: Double) {
        guard settings.isAutoSignalEnabled else {
            print("Auto turn signal is disabled in settings")
            return
        }
        
        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastTriggerTime)
        guard timeSinceLast >= settings.cooldownSeconds else {
            print("Ignored trigger: In cooldown period (\(Int(timeSinceLast))s < \(Int(settings.cooldownSeconds))s)")
            return
        }
        
        if isLeft {
            activateTurnSignal(.left)
        } else {
            activateTurnSignal(.right)
        }
    }
    
    /// Kích hoạt thủ công từ giao diện kiểm thử
    public func triggerManual(state: TurnSignalState) {
        switch state {
        case .left:
            activateTurnSignal(.left)
        case .right:
            activateTurnSignal(.right)
        case .off:
            turnOff()
        }
    }
    
    /// Đổi chiều xi nhan khẩn cấp tức thì (bỏ qua cooldown, xử lý dead-time an toàn) - Dành riêng cho Vòng xoay / Bùng binh
    public func switchTurnDirection(to target: TurnSignalState) {
        guard target != .off else {
            turnOff()
            return
        }
        
        // Ngắt relay chiều cũ trước và trễ 40ms để tránh xung đột relay
        if currentState != .off && currentState != target {
            hardwareService.sendCommand(.turnOff)
            usleep(40_000)
        }
        
        currentState = target
        lastTriggerTime = Date()
        let duration = Int(settings.turnDurationSeconds)
        self.turnDeadline = Date().addingTimeInterval(Double(duration))
        self.remainingSeconds = duration
        self.isBlinkingActive = true
        
        // Gửi lệnh hướng mới tới ESP32
        let cmd: TurnCommand = (target == .left) ? .turnLeft : .turnRight
        hardwareService.sendCommand(cmd)
        
        // Phát âm thanh cảnh báo & giọng nói
        playAlertFeedback(for: target)
        
        // Chạy lại bộ đếm thời gian
        startCountdownTimer(duration: duration)
    }
    
    /// Watchdog độc lập cưỡng chế tắt xi nhan nếu quá thời gian cài đặt (chống tình trạng xi nhan treo hoài không tắt)
    public func enforceWatchdogTimeout() {
        guard currentState != .off else { return }
        let elapsed = Date().timeIntervalSince(lastTriggerTime)
        if elapsed >= settings.turnDurationSeconds {
            print("<<< WATCHDOG CƯỠNG CHẾ TẮT: Đã trôi qua \(Int(elapsed))s >= \(Int(settings.turnDurationSeconds))s! TỰ ĐỘNG TẮT.")
            turnOff(speak: true)
        }
    }
    
    /// Tắt toàn bộ xi nhan (Gửi lệnh kép chống rớt gói)
    public func turnOff(speak: Bool = true) {
        autoOffTimer?.invalidate()
        autoOffTimer = nil
        blinkTimer?.invalidate()
        blinkTimer = nil
        turnDeadline = nil
        
        currentState = .off
        remainingSeconds = 0
        isBlinkingActive = false
        
        // Gửi lệnh TURN_OFF tới ESP32 lần 1
        hardwareService.sendCommand(.turnOff)
        
        // Gửi nhắc lại lệnh TURN_OFF lần 2 sau 60ms để chắc chắn ESP32 nhận được qua BLE/WiFi
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.hardwareService.sendCommand(.turnOff)
        }
        
        if speak {
            speakVoice("Xi nhan đã tắt")
        }
        
        if settings.isHapticFeedbackEnabled {
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.success)
        }
    }
    
    // MARK: - Private Logic
    
    private func activateTurnSignal(_ target: TurnSignalState) {
        guard target != .off else {
            turnOff()
            return
        }
        
        // Nếu đang bật hướng ngược lại, tắt trước để đảm bảo an toàn tuyệt đối
        if currentState != .off && currentState != target {
            hardwareService.sendCommand(.turnOff)
            // Chờ một khoảng rất ngắn để relay nhả ra trước khi đóng relay khác
            usleep(60_000) // 60ms dead time
        }
        
        currentState = target
        lastTriggerTime = Date()
        let duration = Int(settings.turnDurationSeconds)
        turnDeadline = Date().addingTimeInterval(Double(duration))
        remainingSeconds = duration
        isBlinkingActive = true
        
        // Gửi lệnh tương ứng xuống ESP32
        let cmd: TurnCommand = (target == .left) ? .turnLeft : .turnRight
        hardwareService.sendCommand(cmd)
        
        // Phát âm thanh cảnh báo & giọng nói & rung
        playAlertFeedback(for: target)
        
        // Bắt đầu đếm ngược tự tắt trên điện thoại
        startCountdownTimer(duration: duration)
    }
    
    private func startCountdownTimer(duration: Int) {
        autoOffTimer?.invalidate()
        let deadline = Date().addingTimeInterval(Double(duration))
        self.turnDeadline = deadline
        self.remainingSeconds = duration
        
        // Chạy timer trên .common mode để không bị pause khi tương tác màn hình
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let remaining = Int(ceil(deadline.timeIntervalSinceNow))
            if remaining > 0 {
                self.remainingSeconds = remaining
            } else {
                print("<<< WATCHDOG TIMER ĐÃ HẾT HẠN (\(duration)s) -> TẮT XI NHAN")
                self.turnOff(speak: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.autoOffTimer = timer
    }
    
    private func playAlertFeedback(for state: TurnSignalState) {
        if settings.isSoundAlertEnabled {
            AudioServicesPlaySystemSound(1057) // Chuông ngắn cảnh báo
            let text = (state == .left) ? "Đã bật xi nhan trái" : "Đã bật xi nhan phải"
            speakVoice(text)
        }
        
        if settings.isHapticFeedbackEnabled {
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
        }
    }
    
    private func speakVoice(_ text: String) {
        guard settings.isSoundAlertEnabled else { return }
        DispatchQueue.main.async { [weak self] in
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "vi-VN")
            utterance.rate = 0.52
            utterance.volume = 1.0
            self?.speechSynthesizer.speak(utterance)
        }
    }
}
