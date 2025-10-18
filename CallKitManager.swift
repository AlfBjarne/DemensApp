import Foundation
import CallKit
import AVFoundation

class CallKitManager: NSObject, ObservableObject {
    static let shared = CallKitManager()
    
    @Published var hasActiveCall = false
    private let provider: CXProvider
    private var currentCallUUID: UUID?
    
    override init() {
        // Konfigurer CXProvider
        let config = CXProviderConfiguration()
        config.supportsVideo = true
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.includesCallsInRecents = true
        
        provider = CXProvider(configuration: config)
        super.init()
        
        provider.setDelegate(self, queue: nil)
        print("📞 CallKitManager klar")
    }
    
    // Test-funksjon for å simulere anrop
    func testIncomingCall(name: String = "Test Person", number: String = "+47 12345678") {
        print("🧪 Tester innkommende anrop fra \(name)")
        
        let uuid = UUID()
        currentCallUUID = uuid
        
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber, value: number)
        update.localizedCallerName = name
        update.hasVideo = true
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        
        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error = error {
                print("❌ Feil ved test-anrop: \(error.localizedDescription)")
            } else {
                print("✅ Test-anrop vises! Sjekk skjermen.")
            }
        }
    }
    
    // Test med kontakt fra app
    func testIncomingCallFromContact(_ contact: Contact) {
        testIncomingCall(name: contact.name, number: contact.phoneNumber)
    }
    
    // Avslutt anrop
    func endCall() {
        guard let uuid = currentCallUUID else { return }
        
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)
        
        let callController = CXCallController()
        callController.request(transaction) { error in
            if let error = error {
                print("❌ Kunne ikke avslutte anrop: \(error)")
            } else {
                print("📞 Anrop avsluttet")
            }
        }
    }
}

// MARK: - CXProviderDelegate
extension CallKitManager: CXProviderDelegate {
    
    func providerDidReset(_ provider: CXProvider) {
        hasActiveCall = false
        currentCallUUID = nil
        print("📞 CallKit reset")
    }
    
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        print("✅ Bruker svarte på anrop!")
        
        // IKKE konfigurer audio her - la CallKit håndtere det
        // Audio vil bli aktivert av provider delegate metoden under
        
        hasActiveCall = true
        
        // Send notifikasjon til appen
        NotificationCenter.default.post(
            name: Notification.Name("CallAnswered"),
            object: nil,
            userInfo: ["uuid": action.callUUID]
        )
        
        // Fulfill action UTEN å endre audio
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        print("📞 Anrop avsluttet av bruker")
        
        hasActiveCall = false
        currentCallUUID = nil
        
        // Send notifikasjon
        NotificationCenter.default.post(
            name: Notification.Name("CallEnded"),
            object: nil
        )
        
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        print("🔇 Mute: \(action.isMuted)")
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        print("🔊 Audio session aktivert av CallKit")
        
        // Konfigurer audio ETTER at CallKit har aktivert session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.configureAudioForVideoCall()
        }
    }
    
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        print("🔇 Audio session deaktivert av CallKit")
    }
    
    // Separat metode for audio konfigurasjon
    private func configureAudioForVideoCall() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Sjekk om session allerede er aktiv
            if audioSession.category == .playAndRecord {
                print("✅ Audio session allerede konfigurert")
                return
            }
            
            // Konfigurer for video chat med høyttaler
            try audioSession.setCategory(.playAndRecord,
                                        mode: .videoChat,
                                        options: [.defaultToSpeaker, .allowBluetooth])
            
            print("✅ Audio konfigurert for video-samtale")
        } catch {
            print("⚠️ Audio konfigurasjon warning: \(error)")
            // Ikke kritisk - audio fungerer fortsatt
        }
    }
}
