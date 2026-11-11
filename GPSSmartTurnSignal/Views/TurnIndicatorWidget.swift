import SwiftUI

/// Widget hiển thị đồ họa đèn xi nhan nhấp nháy mô phỏng đèn taplo xe máy/ô tô
public struct TurnIndicatorWidget: View {
    @ObservedObject var controller = TurnSignalController.shared
    @State private var isBlinking = false
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 24) {
            // Đèn xi nhan TRÁI
            HStack(spacing: 8) {
                Image(systemName: "arrowtriangle.backward.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(leftColor)
                    .scaleEffect(controller.currentState == .left && isBlinking ? 1.15 : 1.0)
                    .animation(controller.currentState == .left ? Animation.easeInOut(duration: 0.45).repeatForever(autoreverses: true) : .default, value: isBlinking)
                
                Text("TRÁI")
                    .font(.caption.bold())
                    .foregroundColor(controller.currentState == .left ? .green : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(controller.currentState == .left ? Color.green.opacity(0.18) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(controller.currentState == .left ? Color.green : Color.clear, lineWidth: 2)
            )
            
            // Bộ đếm thời gian tự tắt (Watchdog Countdown)
            if controller.currentState != .off {
                VStack(spacing: 2) {
                    Text("\(controller.remainingSeconds)s")
                        .font(.system(size: 20, weight: .heavy, design: .monospaced))
                        .foregroundColor(.orange)
                    Text("Tự tắt")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
            }
            
            // Đèn xi nhan PHẢI
            HStack(spacing: 8) {
                Text("PHẢI")
                    .font(.caption.bold())
                    .foregroundColor(controller.currentState == .right ? .green : .secondary)
                
                Image(systemName: "arrowtriangle.forward.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(rightColor)
                    .scaleEffect(controller.currentState == .right && isBlinking ? 1.15 : 1.0)
                    .animation(controller.currentState == .right ? Animation.easeInOut(duration: 0.45).repeatForever(autoreverses: true) : .default, value: isBlinking)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(controller.currentState == .right ? Color.green.opacity(0.18) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(controller.currentState == .right ? Color.green : Color.clear, lineWidth: 2)
            )
        }
        .onAppear {
            isBlinking = true
        }
    }
    
    private var leftColor: Color {
        if controller.currentState == .left {
            return isBlinking ? Color.green : Color.green.opacity(0.3)
        }
        return Color.gray.opacity(0.3)
    }
    
    private var rightColor: Color {
        if controller.currentState == .right {
            return isBlinking ? Color.green : Color.green.opacity(0.3)
        }
        return Color.gray.opacity(0.3)
    }
}
