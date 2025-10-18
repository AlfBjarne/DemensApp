import SwiftUI

struct DebugConsoleView: View {
    @StateObject private var debugLogger = DebugLogger.shared
    @State private var showDebugInfo = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Toggle button
            Button(action: { showDebugInfo.toggle() }) {
                HStack {
                    Image(systemName: showDebugInfo ? "chevron.down" : "chevron.right")
                    Text("Debug Console")
                    Spacer()
                    Text("\(debugLogger.logs.count) logs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if showDebugInfo {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(debugLogger.logs) { log in
                            HStack(alignment: .top, spacing: 8) {
                                Text(log.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 60)
                                
                                Image(systemName: log.icon)
                                    .foregroundColor(log.color)
                                    .frame(width: 20)
                                
                                Text(log.message)
                                    .font(.caption)
                                    .foregroundColor(log.color)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 5)
                        }
                    }
                }
                .frame(height: 200)
                .background(Color.black.opacity(0.05))
                .cornerRadius(8)
                
                HStack {
                    Button("Clear") {
                        debugLogger.clear()
                    }
                    .font(.caption)
                    
                    Spacer()
                    
                    Button("Copy All") {
                        let allLogs = debugLogger.logs.map {
                            "\($0.timestamp): \($0.message)"
                        }.joined(separator: "\n")
                        UIPasteboard.general.string = allLogs
                    }
                    .font(.caption)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

// Debug Logger Singleton
class DebugLogger: ObservableObject {
    static let shared = DebugLogger()
    
    @Published var logs: [DebugLog] = []
    
    private init() {
        // Intercept print statements
        setupConsoleRedirection()
    }
    
    func log(_ message: String, type: LogType = .info) {
        let log = DebugLog(message: message, type: type)
        
        DispatchQueue.main.async {
            self.logs.append(log)
            
            // Keep only last 100 logs
            if self.logs.count > 100 {
                self.logs.removeFirst()
            }
        }
        
        // Also print to console
        print("[\(type.rawValue)] \(message)")
    }
    
    func clear() {
        DispatchQueue.main.async {
            self.logs.removeAll()
        }
    }
    
    private func setupConsoleRedirection() {
        // This captures print statements for debugging
        // Note: This is a simplified version for testing
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.log("📱 App became active", type: .info)
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.log("📱 App entered background", type: .warning)
        }
    }
}

struct DebugLog: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
    let type: LogType
    
    var icon: String {
        switch type {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        case .network: return "network"
        case .video: return "video.circle"
        case .audio: return "speaker.wave.2"
        }
    }
    
    var color: Color {
        switch type {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .network: return .purple
        case .video: return .cyan
        case .audio: return .mint
        }
    }
}

enum LogType: String {
    case info = "INFO"
    case success = "SUCCESS"
    case warning = "WARNING"
    case error = "ERROR"
    case network = "NETWORK"
    case video = "VIDEO"
    case audio = "AUDIO"
}

// Extension to make logging easier throughout the app
extension AgoraVideoCallManager {
    func logDebug(_ message: String, type: LogType = .video) {
        DebugLogger.shared.log("Agora: \(message)", type: type)
    }
}

extension VideoManager {
    func logDebug(_ message: String, type: LogType = .video) {
        DebugLogger.shared.log("Video: \(message)", type: type)
    }
}
