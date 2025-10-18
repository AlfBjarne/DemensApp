import SwiftUI
import AgoraRtcKit

// MARK: - INTEGRATED CALL VIEW (STABLE VERSION)
struct IntegratedCallView: View {
    let contact: Contact
    @ObservedObject var viewModel: CallViewModel
    @ObservedObject var agoraManager: AgoraVideoCallManager
    let onDismiss: () -> Void
    
    @StateObject private var liftManager = LiftToAnswerManager()
    @State private var hasAnsweredCall = false
    @State private var showCallControls = false
    @State private var callDuration = 0
    @State private var timer: Timer?
    @State private var isSetupComplete = false
    
    var body: some View {
        ZStack {
            // BAKGRUNN - Svart for video
            Color.black
                .ignoresSafeArea()
            
            // MAIN CONTENT
            if isSetupComplete {
                if hasAnsweredCall && agoraManager.isInCall {
                    // LIVE AGORA VIDEO
                    liveVideoView
                } else if hasAnsweredCall {
                    // DEMO VIDEO MODE (hvis Agora feiler)
                    demoVideoView
                } else {
                    // INCOMING CALL SCREEN
                    incomingCallView
                }
                
                // OVERLAY CONTROLS
                if hasAnsweredCall && showCallControls {
                    liveCallControlsOverlay
                }
                
                // CONNECTION STATUS
                if agoraManager.isConnecting {
                    connectionStatusOverlay
                }
            } else {
                // LOADING STATE
                loadingView
            }
        }
        .onAppear {
            setupIntegratedCall()
        }
        .onDisappear {
            cleanup()
        }
        .onTapGesture {
            handleTapGesture()
        }
    }
    
    // MARK: - Live Video View
    private var liveVideoView: some View {
        GeometryReader { geometry in
            ZStack {
                // Remote video (hovedområde)
                if let remoteView = agoraManager.remoteVideoView {
                    AgoraVideoViewRepresentable(view: remoteView)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .background(Color.black)
                } else {
                    // Placeholder medan vi väntar på remote video
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .overlay(
                            VStack(spacing: 20) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                                Text("Venter på video fra \(contact.name)...")
                                    .foregroundColor(.white)
                                    .font(.headline)
                            }
                        )
                }
                
                // Local video (litet vindu øverst til høyre)
                if let localView = agoraManager.localVideoView {
                    VStack {
                        HStack {
                            Spacer()
                            AgoraVideoViewRepresentable(view: localView)
                                .frame(width: 120, height: 90)
                                .background(Color.black)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                                .padding(.trailing, 20)
                                .padding(.top, 50)
                        }
                        Spacer()
                    }
                }
                
                // Call duration overlay
                VStack {
                    HStack {
                        Text("📞 \(formatTime(callDuration))")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(20)
                        Spacer()
                    }
                    .padding(.top, 60)
                    .padding(.leading, 20)
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Demo Video View (fallback)
    private var demoVideoView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 20) {
                Text("📹 Video-samtale")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                
                Text("Med \(contact.name)")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
                
                Text("Varighet: \(formatTime(callDuration))")
                    .font(.subheadline)
                    .foregroundColor(.green)
                
                // DEMO VIDEO PLACEHOLDER
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(
                        colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 300, height: 200)
                    .overlay(
                        VStack {
                            Text("🎥")
                                .font(.system(size: 40))
                            Text("Demo Video-samtale")
                                .foregroundColor(.white)
                                .font(.headline)
                            Text("(Agora ikke tilgjengelig)")
                                .foregroundColor(.white.opacity(0.6))
                                .font(.caption)
                        }
                    )
                    .scaleEffect(1.02)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: hasAnsweredCall)
            }
            
            Spacer()
            
            // End call button
            Button(action: endCall) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 35))
                            .foregroundColor(.white)
                    )
            }
            .padding(.bottom, 50)
        }
    }
    
    // MARK: - Incoming Call View
    private var incomingCallView: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 30) {
                // CALLER INFO
                VStack(spacing: 15) {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .overlay(
                            Text(String(contact.name.first ?? "?"))
                                .font(.system(size: 50, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .scaleEffect(1.05)
                        .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: !hasAnsweredCall)
                    
                    Text("📞 \(contact.name)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Innkommende video-anrop")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                // INSTRUCTIONS
                VStack(spacing: 12) {
                    Text("💙 3 MÅTER Å BESVARE:")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    VStack(spacing: 8) {
                        CallInstructionRow(icon: "🖱️", text: "TRYKK hvor som helst på skjermen")
                        CallInstructionRow(icon: "📱", text: "LØFT eller BEVEG enheten")
                        CallInstructionRow(icon: "🔘", text: "TRYKK grønn SVAR-knapp")
                    }
                }
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(15)
                
                // CALL BUTTONS
                HStack(spacing: 60) {
                    // Decline
                    Button(action: declineCall) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 80, height: 80)
                            .overlay(
                                Image(systemName: "phone.down.fill")
                                    .font(.system(size: 35))
                                    .foregroundColor(.white)
                            )
                            .shadow(color: .red.opacity(0.4), radius: 10, x: 0, y: 5)
                    }
                    
                    // Answer
                    Button(action: answerCall) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 80, height: 80)
                            .scaleEffect(1.1)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: !hasAnsweredCall)
                            .overlay(
                                Image(systemName: "video.fill")
                                    .font(.system(size: 35))
                                    .foregroundColor(.white)
                            )
                            .shadow(color: .green.opacity(0.4), radius: 10, x: 0, y: 5)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Live Call Controls Overlay
    private var liveCallControlsOverlay: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 40) {
                // Video toggle
                Button(action: {
                    DispatchQueue.main.async {
                        agoraManager.toggleLocalVideo()
                    }
                }) {
                    Circle()
                        .fill(agoraManager.isLocalVideoEnabled ? Color.gray.opacity(0.3) : Color.red)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: agoraManager.isLocalVideoEnabled ? "video.fill" : "video.slash.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        )
                }
                
                // Audio toggle
                Button(action: {
                    DispatchQueue.main.async {
                        agoraManager.toggleLocalAudio()
                    }
                }) {
                    Circle()
                        .fill(agoraManager.isLocalAudioEnabled ? Color.gray.opacity(0.3) : Color.red)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: agoraManager.isLocalAudioEnabled ? "mic.fill" : "mic.slash.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        )
                }
                
                // End call
                Button(action: endCall) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        )
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color.black.opacity(0.7))
                    .shadow(radius: 10)
            )
            .padding(.bottom, 50)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - Connection Status Overlay
    private var connectionStatusOverlay: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 15) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                
                Text("Kobler til video-samtale...")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("Vennligst vent...")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.8))
                    .shadow(radius: 15)
            )
            
            Spacer()
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            
            Text("Forbereder anrop...")
                .font(.headline)
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Setup and Actions
    private func setupIntegratedCall() {
        print("🎥 IntegratedCallView startet")
        
        // Setup på main thread med delay for å unngå hang
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Start vibration
            VibrationManager.shared.startCallVibration()
            
            // Start motion detection
            liftManager.startMonitoring {
                DispatchQueue.main.async {
                    if !hasAnsweredCall {
                        print("📱 BEVEGELSE detektert - besvarer anrop")
                        answerCall()
                    }
                }
            }
            
            // Forbered Agora i bakgrunnen
            let channelName = "demens_call_\(Int.random(in: 1000...9999))"
            agoraManager.handleIncomingCall(from: contact, channelName: channelName)
            
            isSetupComplete = true
            
            print("✅ ALLE 3 BESVARELSESMETODER AKTIVERT:")
            print("1. 📱 BEVEGELSE - Løft/beveg enheten")
            print("2. 🖱️ TOUCH - Trykk hvor som helst på skjermen")
            print("3. 🔘 KNAPP - Grønn svar-knapp")
        }
    }
    
    private func handleTapGesture() {
        DispatchQueue.main.async {
            if agoraManager.isInCall {
                showCallControls.toggle()
            } else if !hasAnsweredCall {
                print("🖱️ Screen tap - besvarer anrop")
                answerCall()
            }
        }
    }
    
    private func answerCall() {
        guard !hasAnsweredCall else { return }
        
        print("✅ Besvarer integrert video-anrop")
        
        DispatchQueue.main.async {
            hasAnsweredCall = true
            
            // Stop sensors
            VibrationManager.shared.stopCallVibration()
            liftManager.stopMonitoring()
            
            // Success feedback
            let successFeedback = UINotificationFeedbackGenerator()
            successFeedback.notificationOccurred(.success)
            
            // Start call timer
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                DispatchQueue.main.async {
                    callDuration += 1
                }
            }
            
            // Start Agora connection
            agoraManager.answerIntegratedCall()
            
            // Update ViewModel
            viewModel.answerCall()
            
            print("📞 Video-samtale startet")
        }
    }
    
    private func declineCall() {
        print("❌ Avslår integrert video-anrop")
        
        DispatchQueue.main.async {
            VibrationManager.shared.stopCallVibration()
            liftManager.stopMonitoring()
            
            let errorFeedback = UINotificationFeedbackGenerator()
            errorFeedback.notificationOccurred(.error)
            
            viewModel.declineCall()
            onDismiss()
        }
    }
    
    private func endCall() {
        print("📞 Avslutter integrert video-anrop")
        
        DispatchQueue.main.async {
            timer?.invalidate()
            timer = nil
            showCallControls = false
            
            agoraManager.endCall()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onDismiss()
            }
        }
    }
    
    private func cleanup() {
        DispatchQueue.main.async {
            VibrationManager.shared.stopCallVibration()
            liftManager.stopMonitoring()
            timer?.invalidate()
            timer = nil
            
            print("🧹 IntegratedCallView cleanup")
        }
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Supporting Views

// MARK: - Agora Video View Representable (SAFE VERSION)
struct AgoraVideoViewRepresentable: UIViewRepresentable {
    let view: UIView
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .black
        
        // SIKKER VIEW SETUP - Sjekk at view ikke allerede har superview
        if view.superview == nil {
            containerView.addSubview(view)
            
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: containerView.topAnchor),
                view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
        }
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // SIKKER UPDATE - Fjern eksisterende subviews trygt
        DispatchQueue.main.async {
            uiView.subviews.forEach { subview in
                if subview != view && subview.superview == uiView {
                    subview.removeFromSuperview()
                }
            }
            
            // Legg til view hvis det ikke allerede er der
            if view.superview != uiView && view.superview == nil {
                uiView.addSubview(view)
                
                view.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    view.topAnchor.constraint(equalTo: uiView.topAnchor),
                    view.leadingAnchor.constraint(equalTo: uiView.leadingAnchor),
                    view.trailingAnchor.constraint(equalTo: uiView.trailingAnchor),
                    view.bottomAnchor.constraint(equalTo: uiView.bottomAnchor)
                ])
            }
        }
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        // SIKKER CLEANUP når view fjernes
        DispatchQueue.main.async {
            uiView.subviews.forEach { subview in
                if subview.superview == uiView {
                    subview.removeFromSuperview()
                }
            }
        }
    }
}

// MARK: - Call Instruction Row
struct CallInstructionRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.title2)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white)
            Spacer()
        }
    }
}

#Preview {
    IntegratedCallView(
        contact: Contact(id: UUID(), name: "Tor Harald", phoneNumber: "+47 123 45 678", relationship: "Familie"),
        viewModel: CallViewModel(contact: Contact(id: UUID(), name: "Test", phoneNumber: "", relationship: "Familie")),
        agoraManager: AgoraVideoCallManager(
            videoManager: VideoManager(),
            callViewModel: CallViewModel(contact: Contact(id: UUID(), name: "Test", phoneNumber: "", relationship: "Familie"))
        )
    ) {
        // Dismiss action
    }
}
