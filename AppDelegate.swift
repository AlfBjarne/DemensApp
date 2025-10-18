import UIKit
import CallKit
import AVFoundation

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        print("📱 DemensApp startet med CallKit støtte")
        
        // Konfigurer audio session for app generelt
        // Men IKKE aktiver den - la CallKit håndtere aktivering
        configureAudioSession()
        
        return true
    }
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Bare KONFIGURER, ikke aktiver
            try audioSession.setCategory(.playAndRecord,
                                        mode: .default,
                                        options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            
            // IKKE kall setActive(true) her!
            // La CallKit kontrollere når audio skal aktiveres
            
            print("✅ Audio session forberedt (ikke aktivert)")
        } catch {
            print("⚠️ Audio setup: \(error)")
        }
    }
}
