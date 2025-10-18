import Foundation
import CallKit

struct CallSession {
    let id: UUID
    let contact: Contact
    let startTime: Date
    var endTime: Date?
    var isActive: Bool
    var callType: CallType
    
    enum CallType {
        case incoming
        case outgoing
        case missed
    }
    
    init(contact: Contact, callType: CallType = .incoming) {
        self.id = UUID()
        self.contact = contact
        self.startTime = Date()
        self.endTime = nil
        self.isActive = true
        self.callType = callType
    }
    
    mutating func endCall() {
        self.endTime = Date()
        self.isActive = false
    }
    
    var duration: TimeInterval {
        if let endTime = endTime {
            return endTime.timeIntervalSince(startTime)
        } else {
            return Date().timeIntervalSince(startTime)
        }
    }
    
    var formattedDuration: String {
        let duration = Int(self.duration)
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
