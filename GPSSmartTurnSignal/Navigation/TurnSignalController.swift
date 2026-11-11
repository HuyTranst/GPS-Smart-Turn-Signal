import Foundation
import Combine
import AudioToolbox
import UIKit

/// Bộ điều phối trạng thái đèn xi nhan, chống dội lệnh và quản lý bộ đếm thời gian
public final class TurnSignalController: ObservableObject {
    public static let shared = TurnSignalController()
    
    // MARK: - Published Properties
    @Published public var currentState: TurnSignalState = .off
    @Published public var remainingSeconds: Int = 0
    @Published public var lastTriggerTime: Date = Date.distantPast
    @Published public var isBlinkingActive: Bool = false
    
    private var autoOffTimer: Timer?
    private var blinkTimer: Timer?
    private let hardwareService = HardwareService.shared
    private let settings = AppSettings.shared
    
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
    
    /// Tắt toàn bộ xi nhan
    public func turnOff() {
        autoOffTimer?.invalidate()
        autoOffTimer = nil
        blinkTimer?.invalidate()
        blinkTimer = nil
        
        currentState = .off
        remainingSeconds = 0
        isBlinkingActive = false
        
        // Gửi lệnh TURN_OFF tới ESP32
        hardwareService.sendCommand(.turnOff)
        
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
        remainingSeconds = duration
        isBlinkingActive = true
        
        // Gửi lệnh tương ứng xuống ESP32
        let cmd: TurnCommand = (target == .left) ? .turnLeft : .turnRight
        hardwareService.sendCommand(cmd)
        
        // Phát âm thanh cảnh báo & rung
        playAlertFeedback()
        
        // Bắt đầu đếm ngược tự tắt trên điện thoại
        startCountdownTimer(duration: duration)
    }
    
    private func startCountdownTimer(duration: Int) {
        autoOffTimer?.invalidate()
        remainingSeconds = duration
        
        autoOffTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            if self.remainingSeconds > 1 {
                self.remainingSeconds -= 1
            } else {
                self.turnOff()
            }
        }
    }
    
    private func playAlertFeedback() {
        if settings.isSoundAlertEnabled {
            // Phát âm thanh hệ thống báo hiệu rẽ
            AudioServicesPlaySystemSound(1057) // Chuông ngắn cảnh báo
        }
        
        if settings.isHapticFeedbackEnabled {
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
        }
    }
}
