import SwiftUI
import AVFoundation

// MARK: - VIDEO CALL SIMULATOR
class VideoCallSimulator: ObservableObject {
    @Published var hasIncomingCall = false
    @Published var callerContact: Contact?
    @Published var callDuration = 0
    @Published var isCallActive = false
    
    private var timer: Timer?
    private var ringtonePlayer: AVAudioPlayer?
    
    // Simuler innkommende video-anrop
    func simulateIncomingCall(from contact: Contact) {
        print("📱 SIMULERER INNKOMMENDE VIDEO-ANROP")
        print("📞 Fra: \(contact.name)")
        print("🎥 Type: Video-samtale")
        
        // Sett anropsinformasjon
        callerContact = contact
        hasIncomingCall = true
        
        // Start ringetone
        playRingtone()
        
        // Vibrer
        startVibration()
        
        // Vis fullskjerm innkommende anrop
        print("🔔 Viser innkommende video-anrop UI")
    }
    
    // Svar på anrop
    func answerCall() {
        print("✅ VIDEO-ANROP BESVART")
        
        hasIncomingCall = false
        isCallActive = true
        
        // Stopp ringetone og vibrasjon
        stopRingtone()
        stopVibration()
        
        // Start samtaletimer
        startCallTimer()
        
        // Her kobles Agora video
        print("🎥 Starter Agora video-forbindelse...")
    }
    
    // Avvis anrop
    func declineCall() {
        print("❌ VIDEO-ANROP AVVIST")
        
        hasIncomingCall = false
        callerContact = nil
        
        stopRingtone()
        stopVibration()
    }
    
    // Avslutt aktiv samtale
    func endCall() {
        print("📞 VIDEO-SAMTALE AVSLUTTET")
        print("⏱️ Varighet: \(formatDuration(callDuration))")
        
        isCallActive = false
        callerContact = nil
        callDuration = 0
        
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Private Helpers
    
    private func playRingtone() {
        // Spill standard ringetone
        guard let soundURL = Bundle.main.url(forResource: "ringtone", withExtension: "mp3") else {
            // Bruk system lyd hvis ingen custom ringtone
            AudioServicesPlaySystemSound(1151) // Standard ringetone
            return
        }
        
        do {
            ringtonePlayer = try AVAudioPlayer(contentsOf: soundURL)
            ringtonePlayer?.numberOfLoops = -1 // Loop
            ringtonePlayer?.play()
            print("🔔 Ringetone spiller")
        } catch {
            print("❌ Kunne ikke spille ringetone: \(error)")
            AudioServicesPlaySystemSound(1151)
        }
    }
    
    private func stopRingtone() {
        ringtonePlayer?.stop()
        ringtonePlayer = nil
    }
    
    private func startVibration() {
        // Vibrer hvert 2. sekund
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
            if !self.hasIncomingCall {
                timer.invalidate()
            } else {
                // Kraftig vibrasjon
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                
                // Dobbel vibrasjon for ekstra oppmerksomhet
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                }
            }
        }
    }
    
    private func stopVibration() {
        // Vibrasjon stoppes automatisk når timer invalideres
    }
    
    private func startCallTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.callDuration += 1
        }
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}
