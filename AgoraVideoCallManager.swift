// OPPDATERT AgoraVideoCallManager.swift - Video Fix

import SwiftUI
import AgoraRtcKit
import AVFoundation

class AgoraVideoCallManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isInCall = false
    @Published var isConnecting = false
    @Published var isLocalVideoEnabled = true
    @Published var isLocalAudioEnabled = true
    @Published var remoteUserID: UInt = 0
    @Published var connectionState: AgoraConnectionState = .disconnected
    @Published var callDuration = 0
    
    // MARK: - Video Views (for IntegratedCallView compatibility)
    @Published var localVideoView: UIView?
    @Published var remoteVideoView: UIView?
    
    // MARK: - Private Properties
    private var agoraKit: AgoraRtcEngineKit?
    private var currentChannelName: String?
    private var currentToken: String?
    private var localUID: UInt = 0
    private var callTimer: Timer?
    private let videoManager: VideoManager
    private let callViewModel: CallViewModel
    
    // MARK: - Configuration
    private let appID = "aab8b8f5a8cd4469a63042fcfafe7063" // Demo App ID
    private let tempToken = "007eJxTYHDQ3NnnOWkmk+zKOSqHVfakuc4Tk8t7c9SxIsPiuoRMZ7sCg2VSqmmyZbKBSaKhpUmauZFFoqWlqXlycmqaRWKyUVKyZcfnjIZARoYvGbdYGRkgEMTnZChJLS6JNzQ2sGBgAABfix/0" // Dagens token
    
    // MARK: - Initialization
    init(videoManager: VideoManager, callViewModel: CallViewModel) {
        self.videoManager = videoManager
        self.callViewModel = callViewModel
        super.init()
        
        setupAgoraEngine()
        setupVideoViews()
        print("🎥 Initialiserer Agora Video Engine for DemensApp")
    }
    
    deinit {
        cleanupSync()
    }
    
    nonisolated private func cleanupSync() {
        agoraKit?.delegate = nil
        AgoraRtcEngineKit.destroy()
        print("🧹 Agora deinit cleanup")
    }
    
    // MARK: - Video Views Setup - FORBEDRET
    private func setupVideoViews() {
        Task { @MainActor in
            // Opprett UIViews for video
            self.localVideoView = UIView()
            self.localVideoView?.backgroundColor = UIColor.darkGray
            
            self.remoteVideoView = UIView()
            self.remoteVideoView?.backgroundColor = UIColor.black
            
            print("📹 Video views opprettet")
        }
    }
    
    // MARK: - Agora Engine Setup - FORBEDRET
    private func setupAgoraEngine() {
        let config = AgoraRtcEngineConfig()
        config.appId = appID
        config.channelProfile = .communication
        
        agoraKit = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)
        
        // FORBEDRET: Enable video først
        agoraKit?.enableVideo()
        agoraKit?.enableLocalVideo(true)
        agoraKit?.enableLocalAudio(true)
        
        // FORBEDRET: Bedre video configuration
        let videoConfig = AgoraVideoEncoderConfiguration(
            size: CGSize(width: 640, height: 480),
            frameRate: .fps15,
            bitrate: AgoraVideoBitrateStandard,
            orientationMode: .fixedPortrait,
            mirrorMode: .auto
        )
        agoraKit?.setVideoEncoderConfiguration(videoConfig)
        
        // NYTT: Switch til front camera som default
        agoraKit?.switchCamera()
        
        // FORBEDRET: Camera settings
        agoraKit?.setCameraAutoFocusFaceModeEnabled(true)
        
        print("✅ Agora Engine konfigurert med video")
        print("📹 Front camera aktivert som default")
    }
    
    // MARK: - Call Management - FORBEDRET
    
    @MainActor
    func answerIntegratedCall() {
        guard let channelName = currentChannelName else {
            print("❌ Ingen channel name for å svare på anrop")
            return
        }
        
        print("✅ Besvarer integrert video-anrop")
        print("🔡 Bruker channel: \(channelName)")
        
        if isInCall {
            print("✅ Allerede i channel - aktiverer video/audio publishing")
            
            // FORBEDRET: Force setup local video med mehrere forsøk
            setupLocalVideoCanvas()
            
            // Force enable video flere ganger for å sikre det fungerer
            agoraKit?.enableLocalVideo(false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.agoraKit?.enableLocalVideo(true)
                self.isLocalVideoEnabled = true
                print("📹 Local video force-enabled")
            }
            
            agoraKit?.enableLocalAudio(true)
            
            isConnecting = false
            isLocalAudioEnabled = true
            
            print("📹 Video/audio publishing aktivert")
            
            // NYTT: Ekstra setup efter kort delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.setupLocalVideoCanvas()
                print("📹 Ekstra local video setup")
            }
            
            return
        }
        
        // Join channel med video
        isConnecting = true
        joinChannelWithFallback(channelName: channelName, uid: localUID)
    }
    
    // MARK: - Video Canvas Setup - FORBEDRET
    
    private func setupLocalVideoCanvas() {
        guard let localView = localVideoView,
              let agoraKit = self.agoraKit else {
            print("❌ Local view eller AgoraKit mangler")
            return
        }
        
        print("📹 Setter opp local video canvas")
        
        // FORBEDRET: Clear existing setup først
        let clearCanvas = AgoraRtcVideoCanvas()
        clearCanvas.uid = 0
        clearCanvas.view = nil
        agoraKit.setupLocalVideo(clearCanvas)
        
        // Wait litt, så setup på nytt
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            let videoCanvas = AgoraRtcVideoCanvas()
            videoCanvas.uid = 0
            videoCanvas.view = localView
            videoCanvas.renderMode = .fit
            videoCanvas.mirrorMode = .auto
            
            agoraKit.setupLocalVideo(videoCanvas)
            
            // FORBEDRET: Ensure video is enabled og switch til front camera
            agoraKit.enableLocalVideo(true)
            agoraKit.switchCamera() // Ensure front camera
            
            print("✅ Local video canvas setup fullført med front camera")
        }
    }
    
    private func setupRemoteVideoCanvas(uid: UInt) {
        guard let remoteView = remoteVideoView,
              let agoraKit = self.agoraKit else {
            print("❌ Remote view eller AgoraKit mangler")
            return
        }
        
        print("📹 Setter opp remote video for UID: \(uid)")
        
        let videoCanvas = AgoraRtcVideoCanvas()
        videoCanvas.uid = uid
        videoCanvas.view = remoteView
        videoCanvas.renderMode = .fit
        videoCanvas.mirrorMode = .disabled
        
        agoraKit.setupRemoteVideo(videoCanvas)
        
        print("✅ Remote video setup fullført for UID: \(uid)")
    }
    
    // MARK: - Channel Joining - FORBEDRET
    private func joinChannelWithFallback(channelName: String, uid: UInt, isListeningMode: Bool = false) {
        print("🔧 Kobler til Agora channel: \(channelName)")
        
        if isInCall {
            print("⚠️ Allerede i anrop - avslutter først")
            Task { @MainActor in
                self.endCall()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.joinChannelWithFallback(channelName: channelName, uid: uid, isListeningMode: isListeningMode)
            }
            return
        }
        
        let mediaOptions = AgoraRtcChannelMediaOptions()
        mediaOptions.channelProfile = .communication
        mediaOptions.clientRoleType = .broadcaster
        
        if isListeningMode {
            // For iPad listening mode
            mediaOptions.publishCameraTrack = false
            mediaOptions.publishMicrophoneTrack = false
            mediaOptions.autoSubscribeVideo = true
            mediaOptions.autoSubscribeAudio = true
        } else {
            // FORBEDRET: For active calling - force publish video
            mediaOptions.publishCameraTrack = true
            mediaOptions.publishMicrophoneTrack = true
            mediaOptions.autoSubscribeVideo = true
            mediaOptions.autoSubscribeAudio = true
        }
        
        print("🔄 Kobler til med video publishing: \(!isListeningMode)")
        print("🆔 UID: \(uid)")
        print("🔑 Token: \(tempToken.isEmpty ? "No Token" : "Token provided")")
        
        let result = agoraKit?.joinChannel(
            byToken: tempToken.isEmpty ? nil : tempToken,
            channelId: channelName,
            uid: uid,
            mediaOptions: mediaOptions
        )
        
        if result == 0 {
            print("✅ Channel join initiated")
            
            Task { @MainActor in
                // FORBEDRET: Setup video umiddelbart
                if !isListeningMode {
                    self.setupLocalVideoCanvas()
                }
            }
        } else {
            print("❌ Channel join feilet, kode: \(result ?? -1)")
            
            Task { @MainActor in
                self.isConnecting = false
            }
        }
    }
    
    // MARK: - Video Control - FORBEDRET
    
    @MainActor
    func toggleLocalVideo() {
        isLocalVideoEnabled.toggle()
        agoraKit?.enableLocalVideo(isLocalVideoEnabled)
        
        // NYTT: Re-setup canvas hvis vi aktiverer video
        if isLocalVideoEnabled {
            setupLocalVideoCanvas()
        }
        
        print("📹 Lokal video: \(isLocalVideoEnabled ? "PÅ" : "AV")")
    }
    
    @MainActor
    func toggleLocalAudio() {
        isLocalAudioEnabled.toggle()
        agoraKit?.enableLocalAudio(isLocalAudioEnabled)
        print("🎤 Lokal audio: \(isLocalAudioEnabled ? "PÅ" : "AV")")
    }
    
    // MARK: - Debug Functions - NYTT
    
    func debugVideoSetup() {
        print("\n🎥 === AGORA VIDEO DEBUG ===")
        print("Local video view: \(localVideoView != nil)")
        print("Remote video view: \(remoteVideoView != nil)")
        print("Local video enabled: \(isLocalVideoEnabled)")
        print("Remote user ID: \(remoteUserID)")
        print("Is in call: \(isInCall)")
        print("Is connecting: \(isConnecting)")
        
        if let agoraKit = agoraKit {
            print("AgoraKit initialized: ✅")
        } else {
            print("AgoraKit initialized: ❌")
        }
        
        print("========================\n")
    }
    
    // MARK: - Existing methods (unchanged)
    // ... (resten av metodene forblir som før)
    
    @MainActor
    func startTestCallAsInitiator(channelName: String) {
        print("📱 iPhone starter anrop til channel: \(channelName)")
        
        forceResetConnection()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.currentChannelName = channelName
            self.isConnecting = true
            self.localUID = UInt.random(in: 1000...9999)
            
            print("📱 iPhone bruker UID: \(self.localUID)")
            self.joinChannelWithFallback(channelName: channelName, uid: self.localUID)
        }
    }
    
    @MainActor
    func prepareTestCallAsReceiver(channelName: String) {
        print("🔥 FORBEREDER FOR TEST-ANROP SOM MOTTAKER")
        print("📱 Channel: \(channelName)")
        
        currentChannelName = channelName
        localUID = UInt.random(in: 1000...9999)
        
        print("📱 Lokal bruker ID: \(localUID)")
    }
    
    func joinWaitingRoom(channelName: String) {
        print("📱 iPad joining channel for listening: \(channelName)")
        
        currentChannelName = channelName
        localUID = UInt.random(in: 1000...9999)
        
        print("📱 iPad bruker UID: \(localUID)")
        
        joinChannelWithFallback(channelName: channelName, uid: localUID, isListeningMode: true)
    }
    
    @MainActor
    func handleIncomingCall(from contact: Contact, channelName: String) {
        print("📞 Integrert Agora-anrop fra \(contact.name)")
        currentChannelName = channelName
        localUID = UInt.random(in: 1000...9999)
    }
    
    @MainActor
    func endCall() {
        print("📞 Avslutter Agora video-anrop")
        
        stopCallTimer()
        cleanupVideoViews()
        
        agoraKit?.leaveChannel(nil)
        print("🔌 Left channel immediately")
        
        isInCall = false
        isConnecting = false
        remoteUserID = 0
        currentChannelName = nil
        currentToken = nil
        callDuration = 0
        connectionState = .disconnected
        
        print("🧹 Call state reset fullført")
    }
    
    @MainActor
    func forceResetConnection() {
        print("🔄 FORCE RESET: Nullstiller Agora forbindelse")
        
        agoraKit?.leaveChannel(nil)
        
        isInCall = false
        isConnecting = false
        remoteUserID = 0
        currentChannelName = nil
        currentToken = nil
        callDuration = 0
        connectionState = .disconnected
        
        stopCallTimer()
        
        print("✅ Force reset fullført")
    }
    
    func setupLocalVideo(in view: UIView) {
        guard let agoraKit = self.agoraKit else {
            print("❌ AgoraKit ikke initialiseret")
            return
        }
        
        print("📹 Setter opp lokal video i view")
        
        let videoCanvas = AgoraRtcVideoCanvas()
        videoCanvas.uid = 0
        videoCanvas.view = view
        videoCanvas.renderMode = .fit
        videoCanvas.mirrorMode = .auto
        
        agoraKit.setupLocalVideo(videoCanvas)
        print("✅ Lokal video setup fullført")
    }
    
    func setupRemoteVideo(uid: UInt, in view: UIView) {
        guard let agoraKit = self.agoraKit else {
            print("❌ AgoraKit ikke initialiseret")
            return
        }
        
        print("📹 Setter opp remote video for UID: \(uid)")
        
        let videoCanvas = AgoraRtcVideoCanvas()
        videoCanvas.uid = uid
        videoCanvas.view = view
        videoCanvas.renderMode = .fit
        videoCanvas.mirrorMode = .disabled
        
        agoraKit.setupRemoteVideo(videoCanvas)
        print("✅ Remote video setup fullført for UID: \(uid)")
    }
    
    func enableRemoteVideo(_ enabled: Bool, for uid: UInt) {
        guard let agoraKit = self.agoraKit else { return }
        
        agoraKit.muteRemoteVideoStream(uid, mute: !enabled)
        print("📹 Remote video fra UID \(uid): \(enabled ? "AKTIVERT" : "DEAKTIVERT")")
    }
    
    func cleanupVideoViews() {
        guard let agoraKit = self.agoraKit else { return }
        
        let localCanvas = AgoraRtcVideoCanvas()
        localCanvas.uid = 0
        localCanvas.view = nil
        agoraKit.setupLocalVideo(localCanvas)
        
        if remoteUserID > 0 {
            let remoteCanvas = AgoraRtcVideoCanvas()
            remoteCanvas.uid = remoteUserID
            remoteCanvas.view = nil
            agoraKit.setupRemoteVideo(remoteCanvas)
        }
        
        print("🧹 Video views cleanup fullført")
    }
    
    @MainActor
    private func startCallTimer() {
        callTimer?.invalidate()
        callDuration = 0
        
        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.callDuration += 1
            }
        }
    }
    
    @MainActor
    private func stopCallTimer() {
        callTimer?.invalidate()
        callTimer = nil
    }
    
    func requestPermissions() async -> Bool {
        let audioPermission = await requestAudioPermission()
        let videoPermission = await requestVideoPermission()
        
        print("🎤 Audio permission: \(audioPermission)")
        print("📹 Video permission: \(videoPermission)")
        
        return audioPermission && videoPermission
    }
    
    private func requestAudioPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    private func requestVideoPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    func getConnectionStateDescription() -> String {
        switch connectionState {
        case .disconnected:
            return "Frakoblet"
        case .connecting:
            return "Kobler til..."
        case .connected:
            return "Tilkoblet"
        case .reconnecting:
            return "Gjenoppretter..."
        case .failed:
            return "Feilet"
        @unknown default:
            return "Ukjent"
        }
    }
    
    func formatCallDuration() -> String {
        let minutes = callDuration / 60
        let seconds = callDuration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - AgoraRtcEngineDelegate - FORBEDRET

extension AgoraVideoCallManager: AgoraRtcEngineDelegate {
    
    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        print("✅ Agora: Koblet til channel '\(channel)' med UID: \(uid)")
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isInCall = true
            self.isConnecting = false
            self.startCallTimer()
            
            // FORBEDRET: Setup local video umiddelbart etter join
            self.setupLocalVideoCanvas()
        }
        
        print("🎬 SEAMLESS TRANSITION: Pre-call → Live Agora video")
        print("✅ Live Agora video-samtale aktiv")
    }
    
    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        print("👥 Agora: Remote bruker koblet på: \(uid)")
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.remoteUserID = uid
            self.setupRemoteVideoCanvas(uid: uid)
        }
        
        print("📹 Setter opp remote video for bruker: \(uid)")
    }
    
    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        print("👋 Remote bruker \(uid) koblet fra")
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if uid == self.remoteUserID {
                self.remoteUserID = 0
            }
        }
    }
    
    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, connectionChangedTo state: AgoraConnectionState, reason: AgoraConnectionChangedReason) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.connectionState = state
        }
        
        switch state {
        case .disconnected:
            print("🔗 Agora connection state: DISCONNECTED")
        case .connecting:
            print("🔗 Agora connection state: CONNECTING")
        case .connected:
            print("🔗 Agora connection state: CONNECTED")
            print("✅ Agora forbindelse etablert")
        case .reconnecting:
            print("🔗 Agora connection state: RECONNECTING")
        case .failed:
            print("🔗 Agora connection state: FAILED")
            print("❌ Agora forbindelse feilet")
        @unknown default:
            print("🔗 Agora connection state: UNKNOWN")
        }
    }
    
    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        print("❌ Agora error: \(errorCode.rawValue)")
    }
    
    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurWarning warningCode: AgoraWarningCode) {
        print("⚠️ Agora warning: \(warningCode.rawValue)")
    }
    
    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, firstLocalVideoFrameWith size: CGSize, elapsed: Int) {
        print("📹 Første lokal video frame: \(size)")
    }
    
    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, firstRemoteVideoDecodedOfUid uid: UInt, size: CGSize, elapsed: Int) {
        print("📹 Første remote video frame mottatt fra UID: \(uid), størrelse: \(size)")
    }
}
