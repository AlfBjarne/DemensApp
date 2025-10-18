import SwiftUI
import AVFoundation
import Speech
import CallKit

// MARK: - Call ViewModel
class CallViewModel: ObservableObject {
    @Published var callerName: String = ""
    @Published var isCallActive: Bool = false
    
    private let contact: Contact
    
    init(contact: Contact) {
        self.contact = contact
        self.callerName = contact.name
    }
    
    func answerCall() {
        print("✅ CallViewModel: Anrop besvart for \(callerName)")
        isCallActive = true
        
        // Simuler anrops-accept
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            print("📱 Anrop etablert med \(self.callerName)")
            // Her kan du legge til ekte CallKit logikk senere
        }
    }
    
    func declineCall() {
        print("❌ CallViewModel: Anrop avslått for \(callerName)")
        isCallActive = false
        
        // Simuler anrops-avvisning
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            print("📱 Anrop avsluttet")
            // Her kan du legge til ekte CallKit logikk senere
        }
    }
}
