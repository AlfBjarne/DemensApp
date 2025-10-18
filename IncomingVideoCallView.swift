import SwiftUI
import AVFoundation
import AVKit
import CoreMotion
import AgoraRtcKit

// MARK: - INCOMING VIDEO CALL VIEW - MED AGORA VIDEO SUPPORT
struct IncomingVideoCallView: View {
    @ObservedObject var simulator: VideoCallSimulator
    @ObservedObject var videoManager: VideoManager
    @ObservedObject var agoraManager: AgoraVideoCallManager
    
    @State private var hasAnsweredCall = false
    @State private var showAnswerButtons = false
    @StateObject private var liftManager = LiftToAnswerManager()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let contact = simulator.callerContact {
                if simulator.isCallActive {
                    // AKTIV VIDEO-SAMTALE MED AGORA
                    activeVideoCallView(contact: contact)
                } else {
                    // INNKOMMENDE ANROP MED INSTRUKSJONSVIDEO
                    incomingCallWithVideo(contact: contact)
                }
            }
        }
        .onAppear {
            startInstructionVideo()
            setupMotionDetection()
        }
        .onDisappear {
            cleanup()
            liftManager.stopMonitoring()
        }
    }
    
    // MARK: - Innkommende anrop med instruksjonsvideo
    private func incomingCallWithVideo(contact: Contact) -> some View {
        ZStack {
            // INSTRUKSJONSVIDEO SPILLER I BAKGRUNNEN
            if let player = videoManager.getPlayer() {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        player.play()
                    }
            } else {
                Color.gray.opacity(0.3)
                    .ignoresSafeArea()
            }
            
            // TOUCH-OMRÅDE
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if showAnswerButtons && !hasAnsweredCall {
                        print("🖱️ Skjerm trykket - svarer på anrop")
                        answerCall()
                    }
                }
            
            // OVERLAY MED ANROPS-INFO
            VStack {
                // TOP INFO
                VStack(spacing: 10) {
                    Text("📞 INNKOMMENDE ANROP")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 15)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(20)
                    
                    HStack(spacing: 15) {
                        Circle()
                            .fill(Color.blue.opacity(0.8))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Text(String(contact.name.first ?? "?"))
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text(contact.name)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("Din \(contact.relationship.lowercased())")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(15)
                }
                .padding(.top, 20)
                .padding(.horizontal)
                
                Spacer()
                
                // BUNN SEKSJON MED INSTRUKSJONER OG KNAPPER
                VStack(spacing: 20) {
                    if showAnswerButtons {
                        VStack(spacing: 15) {
                            Text("💚 SVAR PÅ EN AV DISSE MÅTENE:")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                            
                            HStack(spacing: 30) {
                                VStack {
                                    Image(systemName: "hand.tap.fill")
                                        .font(.title2)
                                        .foregroundColor(.yellow)
                                    Text("TRYKK")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                                
                                VStack {
                                    Image(systemName: "iphone.radiowaves.left.and.right")
                                        .font(.title2)
                                        .foregroundColor(.yellow)
                                    Text("LØFT")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                                
                                VStack {
                                    Image(systemName: "phone.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.yellow)
                                    Text("KNAPP")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .padding(15)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(15)
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    // SVAR/AVVIS KNAPPER
                    HStack(spacing: 100) {
                        Button(action: declineCall) {
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 120, height: 120)
                                    .overlay(
                                        Image(systemName: "phone.down.fill")
                                            .font(.system(size: 50))
                                            .foregroundColor(.white)
                                    )
                                    .shadow(color: .red.opacity(0.5), radius: 10)
                                
                                Text("AVVIS")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                            }
                        }
                        
                        Button(action: answerCall) {
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 120, height: 120)
                                    .overlay(
                                        Image(systemName: "video.fill")
                                            .font(.system(size: 50))
                                            .foregroundColor(.white)
                                    )
                                    .shadow(color: .green.opacity(0.5), radius: 15)
                                    .scaleEffect(showAnswerButtons ? 1.1 : 1.0)
                                    .animation(
                                        .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                                        value: showAnswerButtons
                                    )
                                
                                Text("SVAR")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
                .padding(.bottom, 30)
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Aktiv video-samtale MED AGORA VIDEO
    private func activeVideoCallView(contact: Contact) -> some View {
        GeometryReader { geometry in
            ZStack {
                // REMOTE VIDEO (fra iPhone) - FULLSCREEN
                if agoraManager.isInCall && agoraManager.remoteUserID > 0 {
                    AgoraRemoteVideoView(
                        agoraManager: agoraManager,
                        remoteUID: agoraManager.remoteUserID
                    )
                    .ignoresSafeArea()
                    .background(Color.black)
                } else {
                    // FALLBACK HVIS INGEN REMOTE VIDEO
                    Color.black.ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(2.0)
                            .tint(.white)
                        
                        Text("Kobler til video...")
                            .font(.title2)
                            .foregroundColor(.white)
                        
                        if agoraManager.remoteUserID == 0 {
                            Text("Venter på \(contact.name)")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
                
                // LOKAL VIDEO (iPad kamera) - LITE VINDU I HJØRNET
                if agoraManager.isLocalVideoEnabled {
                    VStack {
                        HStack {
                            Spacer()
                            
                            AgoraLocalVideoView(agoraManager: agoraManager)
                                .frame(width: 120, height: 160)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white, lineWidth: 2)
                                )
                                .shadow(radius: 10)
                                .padding(.top, 60)
                                .padding(.trailing, 20)
                        }
                        
                        Spacer()
                    }
                }
                
                // TOP INFO BAR
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 12, height: 12)
                                
                                Text("I samtale med \(contact.name)")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            
                            Text("Varighet: \(formatTime(simulator.callDuration))")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        Spacer()
                        
                        // CONNECTION STATUS
                        VStack(alignment: .trailing, spacing: 5) {
                            if agoraManager.isInCall {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                    Text("Tilkoblet")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                            
                            if agoraManager.remoteUserID > 0 {
                                Text("UID: \(agoraManager.remoteUserID)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 50)
                    .padding(.bottom, 15)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.8), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    Spacer()
                }
                
                // KONTROLLER NEDERST
                VStack {
                    Spacer()
                    
                    // BOTTOM GRADIENT
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 200)
                    .overlay(
                        HStack(spacing: 60) {
                            // TOGGLE VIDEO
                            Button(action: { agoraManager.toggleLocalVideo() }) {
                                VStack(spacing: 8) {
                                    Circle()
                                        .fill(agoraManager.isLocalVideoEnabled ? Color.gray.opacity(0.5) : Color.red)
                                        .frame(width: 70, height: 70)
                                        .overlay(
                                            Image(systemName: agoraManager.isLocalVideoEnabled ? "video.fill" : "video.slash.fill")
                                                .font(.system(size: 30))
                                                .foregroundColor(.white)
                                        )
                                    
                                    Text(agoraManager.isLocalVideoEnabled ? "Video På" : "Video Av")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                            
                            // AVSLUTT SAMTALE
                            Button(action: endCall) {
                                VStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 90, height: 90)
                                        .overlay(
                                            Image(systemName: "phone.down.fill")
                                                .font(.system(size: 40))
                                                .foregroundColor(.white)
                                        )
                                        .shadow(color: .red.opacity(0.5), radius: 10)
                                    
                                    Text("AVSLUTT")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.red)
                                }
                            }
                            
                            // TOGGLE AUDIO
                            Button(action: { agoraManager.toggleLocalAudio() }) {
                                VStack(spacing: 8) {
                                    Circle()
                                        .fill(agoraManager.isLocalAudioEnabled ? Color.gray.opacity(0.5) : Color.red)
                                        .frame(width: 70, height: 70)
                                        .overlay(
                                            Image(systemName: agoraManager.isLocalAudioEnabled ? "mic.fill" : "mic.slash.fill")
                                                .font(.system(size: 30))
                                                .foregroundColor(.white)
                                        )
                                    
                                    Text(agoraManager.isLocalAudioEnabled ? "Lyd På" : "Lyd Av")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .padding(.bottom, 40)
                    )
                }
            }
        }
    }
    
    // MARK: - Setup Motion Detection
    private func setupMotionDetection() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            liftManager.startMonitoring {
                if showAnswerButtons && !hasAnsweredCall {
                    print("📱 LØFTE-BEVEGELSE detektert - svarer")
                    answerCall()
                }
            }
            print("📱 Bevegelse-deteksjon aktivert")
        }
    }
    
    // MARK: - Start Instruction Video
    private func startInstructionVideo() {
        guard let contact = simulator.callerContact else { return }
        
        print("📹 STARTER INSTRUKSJONSVIDEO MED EN GANG")
        
        if !contact.instructionVideoURL.isEmpty {
            videoManager.playVideo(for: contact)
            print("▶️ Instruksjonsvideo spiller: \(contact.instructionVideoURL)")
        } else {
            print("⚠️ Ingen instruksjonsvideo for \(contact.name)")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                showAnswerButtons = true
                print("✅ Svar-knapper aktivert - bruker kan nå svare")
            }
            startVibration()
        }
    }
    
    // MARK: - Answer Call
    private func answerCall() {
        guard !hasAnsweredCall else { return }
        
        hasAnsweredCall = true
        print("✅ BRUKER SVARTE PÅ ANROP")
        
        liftManager.stopMonitoring()
        videoManager.completelyStopVideo()
        stopVibration()
        
        simulator.answerCall()
        
        if let contact = simulator.callerContact {
            startAgoraCall(contact: contact)
        }
    }
    
    // MARK: - Decline Call
    private func declineCall() {
        print("❌ Bruker avviste anrop")
        cleanup()
        simulator.declineCall()
        dismiss()
    }
    
    // MARK: - End Call
    private func endCall() {
        print("📞 Avslutter samtale")
        cleanup()
        simulator.endCall()
        agoraManager.endCall()
        dismiss()
    }
    
    // MARK: - Start Agora Call
    private func startAgoraCall(contact: Contact) {
        let channelName = "test_1308" // Bruk samme channel som iPhone
        print("🎥 Starter Agora video med channel: \(channelName)")
        
        agoraManager.handleIncomingCall(from: contact, channelName: channelName)
        agoraManager.answerIntegratedCall()
        
        print("✅ Agora call startet for \(contact.name)")
    }
    
    // MARK: - Vibration
    private func startVibration() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        
        for i in 0...2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.5) {
                impactFeedback.impactOccurred()
            }
        }
    }
    
    private func stopVibration() {
        // Vibrasjon stopper automatisk
    }
    
    // MARK: - Cleanup
    private func cleanup() {
        videoManager.completelyStopVideo()
        liftManager.stopMonitoring()
    }
    
    // MARK: - Format Time
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - AGORA VIDEO VIEWS
struct AgoraRemoteVideoView: UIViewRepresentable {
    let agoraManager: AgoraVideoCallManager
    let remoteUID: UInt
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.black
        
        // Setup remote video
        DispatchQueue.main.async {
            agoraManager.setupRemoteVideo(uid: remoteUID, in: view)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update if needed
    }
}

struct AgoraLocalVideoView: UIViewRepresentable {
    let agoraManager: AgoraVideoCallManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.darkGray
        
        // Setup local video
        DispatchQueue.main.async {
            agoraManager.setupLocalVideo(in: view)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update if needed
    }
}
