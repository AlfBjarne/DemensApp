import SwiftUI
import AVFoundation
import Speech
import CallKit
import CoreMotion

// MARK: - VIBRASJON MANAGER (UENDRET)
class VibrationManager {
    static let shared = VibrationManager()
    private var vibrationTimer: Timer?
    
    func startCallVibration() {
        print("📳 Starter anrops-vibrasjon")
        
        // Umiddelbar vibrasjon
        triggerVibration()
        
        // Gjentatt vibrasjon hvert 2. sekund
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.triggerVibration()
        }
    }
    
    func stopCallVibration() {
        print("📳 Stopper anrops-vibrasjon")
        vibrationTimer?.invalidate()
        vibrationTimer = nil
    }
    
    private func triggerVibration() {
        // Kraftig vibrasjon for anrop
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        // Ekstra vibrasjon for å gjøre det mer merkbart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            impactFeedback.impactOccurred()
        }
        
        print("📳 Vibrasjon utført")
    }
}

// MARK: - BEVEGELSE-DETEKSJON MANAGER (UENDRET)
class LiftToAnswerManager: ObservableObject {
    private let motionManager = CMMotionManager()
    private var isMonitoring = false
    private var onLiftDetected: (() -> Void)?
    private var lastMovementTime = Date()
    
    func startMonitoring(onLift: @escaping () -> Void) {
        print("📱 Starter BEVEGELSE-deteksjon for anrop")
        self.onLiftDetected = onLift
        
        guard motionManager.isAccelerometerAvailable else {
            print("❌ Accelerometer ikke tilgjengelig")
            return
        }
        
        motionManager.accelerometerUpdateInterval = 0.2
        isMonitoring = true
        
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data, self.isMonitoring else { return }
            
            if let error = error {
                print("❌ Accelerometer feil: \(error.localizedDescription)")
                return
            }
            
            self.detectMovement(data)
        }
        
        print("✅ BEVEGELSE-deteksjon startet")
    }
    
    private func detectMovement(_ data: CMAccelerometerData) {
        // Beregn total bevegelse
        let totalAcceleration = abs(data.acceleration.x) + abs(data.acceleration.y) + abs(data.acceleration.z)
        
        // Lavere terskel for å fange opp mer bevegelse
        let movementThreshold: Double = 1.5
        
        if totalAcceleration > movementThreshold {
            let timeSinceLastMovement = Date().timeIntervalSince(lastMovementTime)
            
            if timeSinceLastMovement > 1.0 {
                print("📱 BEVEGELSE DETEKTERT! Total akselerasjon: \(String(format: "%.3f", totalAcceleration))")
                print("📱 BEVEGELSE trigger - besvarer anrop")
                
                // Trigger anrops-besvarelse
                onLiftDetected?()
                
                // Stopp monitoring
                stopMonitoring()
            }
            
            lastMovementTime = Date()
        }
    }
    
    func stopMonitoring() {
        print("📱 Stopper BEVEGELSE-deteksjon")
        isMonitoring = false
        motionManager.stopAccelerometerUpdates()
        onLiftDetected = nil
    }
    
    deinit {
        stopMonitoring()
    }
}

// MARK: - FACETIME-KOMPATIBEL CALL VIEW (UTEN STEMMEGJENKJENNING)
struct TrueFullScreenCallView: View {
    let contact: Contact
    @ObservedObject var viewModel: CallViewModel
    let onDismiss: () -> Void
    
    // FJERNET: SpeechManager som forårsaket konflikt
    @StateObject private var liftManager = LiftToAnswerManager()
    @State private var hasAnsweredCall = false
    
    var body: some View {
        ZStack {
            // GJENNOMSIKTIG BAKGRUNN - UNIVERSAL TOUCH HANDLER
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !hasAnsweredCall {
                        print("🖱️ BAKGRUNN TRYKK detektert - besvarer anrop")
                        answerCall()
                    }
                }
            
            // INTERFACE
            VStack {
                Spacer()
                
                // INSTRUKSJONER - OPPDATERT UTEN STEMME
                if !hasAnsweredCall {
                    VStack(spacing: 10) {
                        Text("💙 3 MÅTER Å BESVARE:")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Text("🖱️")
                                    .font(.title2)
                                Text("TRYKK hvor som helst på skjermen")
                                    .font(.headline)
                                    .foregroundColor(.cyan)
                            }
                            
                            HStack(spacing: 8) {
                                Text("📱")
                                    .font(.title2)
                                Text("LØFT eller BEVEG enheten")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                
                                Image(systemName: "hand.raised.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)
                                    .scaleEffect(1.2)
                                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: !hasAnsweredCall)
                            }
                            
                            HStack(spacing: 8) {
                                Text("🔘")
                                    .font(.title2)
                                Text("TRYKK grønn SVAR-knapp")
                                    .font(.headline)
                                    .foregroundColor(.yellow)
                            }
                        }
                        
                        // VIBRASJON INDIKATOR
                        HStack(spacing: 8) {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .font(.title2)
                                .foregroundColor(.orange)
                                .scaleEffect(1.1)
                                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: !hasAnsweredCall)
                            
                            Text("📳 Kraftig vibrasjon aktiv")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                        
                        // MULTITASKING INFO
                        Text("✅ FaceTime-kompatibel - Ingen audio-konflikt")
                            .font(.caption)
                            .foregroundColor(.green)
                            .opacity(0.8)
                    }
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(15)
                    .padding(.horizontal, 25)
                    .padding(.bottom, 20)
                }
                
                // ANROPS-INFO
                HStack(spacing: 15) {
                    VStack(spacing: 4) {
                        Text("📞 \(contact.name)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Innkommende anrop...")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        
                        if hasAnsweredCall {
                            Text("✅ Anrop besvart!")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                    }
                    
                    Spacer()
                    
                    // KNAPPER
                    if !hasAnsweredCall {
                        HStack(spacing: 20) {
                            // Avslå knapp
                            Button(action: {
                                print("❌ Avslår anrop med rød knapp")
                                declineCall()
                            }) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 70, height: 70)
                                    .overlay(
                                        VStack {
                                            Image(systemName: "phone.down.fill")
                                                .font(.system(size: 28))
                                                .foregroundColor(.white)
                                            Text("AVSLÅ")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                        }
                                    )
                            }
                            
                            // Svar knapp - ANIMERT
                            Button(action: {
                                print("🔘 Svarer anrop med grønn knapp")
                                answerCall()
                            }) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 70, height: 70)
                                    .scaleEffect(!hasAnsweredCall ? 1.1 : 1.0)
                                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: !hasAnsweredCall)
                                    .overlay(
                                        VStack {
                                            Image(systemName: "phone.fill")
                                                .font(.system(size: 28))
                                                .foregroundColor(.white)
                                            Text("SVAR")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                        }
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(Color.black.opacity(0.85))
                        .shadow(radius: 10)
                )
                .padding(.horizontal, 30)
                .padding(.bottom, 50)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onAppear {
            print("📱 KOMPLETT CallView - 3 METODER AKTIVERT (FACETIME-KOMPATIBEL)")
            
            // Start vibrasjon
            VibrationManager.shared.startCallVibration()
            
            // Start bevegelse-deteksjon
            liftManager.startMonitoring {
                if !hasAnsweredCall {
                    print("📱 BEVEGELSE trigger - besvarer anrop")
                    answerCall()
                }
            }
            
            // STEMMEGJENKJENNING DEAKTIVERT - unngår FaceTime-konflikt
            print("🎤 STEMMEGJENKJENNING DEAKTIVERT - unngår FaceTime audio session konflikt")
            
            print("✅ ALLE 3 BESVARELSESMETODER AKTIVERT:")
            print("1. 📱 BEVEGELSE - Løft/beveg enheten")
            print("2. 🖱️ TOUCH - Trykk hvor som helst på skjermen")
            print("3. 🔘 KNAPP - Grønn svar-knapp")
        }
        .onDisappear {
            print("🧹 KOMPLETT CallView cleanup")
            VibrationManager.shared.stopCallVibration()
            liftManager.stopMonitoring()
        }
    }
    
    private func answerCall() {
        print("✅ KOMPLETT answerCall() - STOPPER ALLE SENSORER")
        hasAnsweredCall = true
        
        // Stopp alt
        VibrationManager.shared.stopCallVibration()
        liftManager.stopMonitoring()
        
        // Bekreftende vibrasjon
        let successFeedback = UINotificationFeedbackGenerator()
        successFeedback.notificationOccurred(.success)
        
        print("✅ Anrop besvart - video fortsetter i ContentView")
        viewModel.answerCall()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            onDismiss()
        }
    }
    
    private func declineCall() {
        print("❌ KOMPLETT declineCall() - STOPPER ALLE SENSORER")
        
        VibrationManager.shared.stopCallVibration()
        liftManager.stopMonitoring()
        
        let errorFeedback = UINotificationFeedbackGenerator()
        errorFeedback.notificationOccurred(.error)
        
        viewModel.declineCall()
        onDismiss()
    }
}
