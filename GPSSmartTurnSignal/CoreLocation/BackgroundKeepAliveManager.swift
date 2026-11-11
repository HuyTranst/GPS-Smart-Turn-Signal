import Foundation
import AVFoundation
import UIKit

/// Quản lý duy trì hoạt động ngầm liên tục 100% khi màn hình tắt hoặc thoát ứng dụng
public final class BackgroundKeepAliveManager: NSObject {
    public static let shared = BackgroundKeepAliveManager()
    
    private var audioPlayer: AVAudioPlayer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var isRunning = false
    
    private override init() {
        super.init()
    }
    
    /// Bắt đầu duy trì ứng dụng chạy ngầm liên tục
    public func startKeepAlive() {
        guard !isRunning else { return }
        isRunning = true
        
        // 1. Cấu hình AVAudioSession chế độ dẫn đường chạy nền
        setupAudioSession()
        
        // 2. Kích hoạt phát âm thanh nền im lặng vô hạn
        startSilentAudioPlayer()
        
        // 3. Đăng ký lắng nghe sự kiện ứng dụng vào background / ra foreground
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        print("Background Keep-Alive STARTED successfully.")
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .voicePrompt, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
        } catch {
            print("Background audio session setup error: \(error.localizedDescription)")
        }
    }
    
    @objc private func handleDidEnterBackground() {
        print("App entered background -> Ensuring Background Task & Audio KeepAlive")
        // Đăng ký Background Task dự phòng
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "GPSSmartTurnSignalKeepAlive") { [weak self] in
            self?.endBackgroundTask()
        }
        
        // Đảm bảo audio session vẫn đang chạy
        if audioPlayer == nil || audioPlayer?.isPlaying == false {
            startSilentAudioPlayer()
        }
    }
    
    @objc private func handleWillEnterForeground() {
        print("App returned to foreground")
        endBackgroundTask()
    }
    
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    
    /// Tạo và phát file âm thanh im lặng (Silent WAV) trong bộ nhớ RAM
    private func startSilentAudioPlayer() {
        // Tạo file WAV PCM 8000Hz 8-bit Mono im lặng độ dài 1 giây
        let sampleRate: UInt32 = 8000
        let numSamples: UInt32 = 8000
        let dataSize: UInt32 = numSamples
        let fileSize: UInt32 = 36 + dataSize
        
        var wav = Data()
        // RIFF header
        wav.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        wav.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        wav.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        // fmt chunk
        wav.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        let fmtChunkSize: UInt32 = 16
        wav.append(contentsOf: withUnsafeBytes(of: fmtChunkSize.littleEndian) { Array($0) })
        let audioFormat: UInt16 = 1 // PCM
        wav.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Array($0) })
        let numChannels: UInt16 = 1 // Mono
        wav.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        let byteRate: UInt32 = sampleRate * 1 // 8000 * 1 byte
        wav.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        let blockAlign: UInt16 = 1
        wav.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        let bitsPerSample: UInt16 = 8
        wav.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        // data chunk
        wav.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        wav.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        
        // 8000 byte mức 128 (im lặng tuyệt đối trong chuẩn PCM 8-bit)
        let silenceBytes = [UInt8](repeating: 128, count: Int(numSamples))
        wav.append(contentsOf: silenceBytes)
        
        do {
            audioPlayer = try AVAudioPlayer(data: wav)
            audioPlayer?.numberOfLoops = -1 // Lặp vô hạn
            audioPlayer?.volume = 0.01 // Mức âm lượng siêu nhỏ (không phát ra tiếng động nào)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            print("Silent keep-alive audio player started (infinite loop).")
        } catch {
            print("Failed to initialize silent audio player: \(error.localizedDescription)")
        }
    }
}
