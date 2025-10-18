import SwiftUI
import AVFoundation
import AVKit

@MainActor
class VideoManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var currentContact: Contact?
    @Published var volume: Float = 1.0
    
    private var loopTimer: Timer?
    private var playerStatusObserver: NSKeyValueObservation?
    private var playerItemStatusObserver: NSKeyValueObservation?
    
    init() {
        print("🎥 VideoManager initialiseret med loop-funksjonalitet")
        setupAudioSession()
    }
    
    deinit {
        cleanupSync()
    }
    
    // MARK: - Sync Cleanup for deinit
    nonisolated private func cleanupSync() {
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        print("🧹 VideoManager deinit cleanup")
    }
    
    // MARK: - Audio Session Setup - FIKSET FOR LYD
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // RIKTIG: Bruk .playAndRecord med defaultToSpeaker for video med lyd på høyttaler
            try audioSession.setCategory(.playAndRecord,
                                        mode: .videoChat,  // Bruker videoChat mode
                                        options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            
            // Aktiver audio session for avspilling
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Route audio til høyttaler
            try audioSession.overrideOutputAudioPort(.speaker)
            
            print("✅ Audio session konfigurert for video med lyd på høyttaler")
            print("🔊 Audio route: \(audioSession.currentRoute.outputs.first?.portName ?? "Unknown")")
        } catch {
            print("❌ Audio session setup feilet: \(error)")
            
            // Fallback til enklere konfigurasjon
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
                try audioSession.setActive(true)
                print("✅ Fallback audio session aktivert")
            } catch {
                print("❌ Fallback også feilet: \(error)")
            }
        }
    }
    
    // MARK: - Play Video - FORBEDRET
    func playVideo(for contact: Contact) {
        print("🎥 Spiller video for: \(contact.name)")
        
        // Stopp eksisterende video helt
        completelyStopVideo()
        
        // Sett ny kontakt
        currentContact = contact
        
        // Start ny video
        loadAndPlayVideo(contact: contact)
    }
    
    private func loadAndPlayVideo(contact: Contact) {
        guard !contact.instructionVideoURL.isEmpty else {
            print("❌ Ingen video URL for \(contact.name)")
            return
        }
        
        // Finn video fil
        guard let videoURL = getVideoURL(for: contact.instructionVideoURL) else {
            print("❌ Kunne ikke finne video: \(contact.instructionVideoURL)")
            return
        }
        
        print("✅ Fant lokal video: \(contact.instructionVideoURL)")
        
        // Opprett ny player med lyd aktivert
        let playerItem = AVPlayerItem(url: videoURL)
        
        // VIKTIG: Konfigurer audio mix for å sikre lyd
        let audioMix = AVMutableAudioMix()
        if let audioTrack = playerItem.asset.tracks(withMediaType: .audio).first {
            let audioMixInputParams = AVMutableAudioMixInputParameters(track: audioTrack)
            audioMixInputParams.setVolume(1.0, at: .zero)
            audioMix.inputParameters = [audioMixInputParams]
        }
        playerItem.audioMix = audioMix
        
        player = AVPlayer(playerItem: playerItem)
        
        // VIKTIG: Sett volum og lyd-innstillinger
        player?.volume = 1.0
        player?.isMuted = false
        
        // Allow background audio to mix
        player?.audiovisualBackgroundPlaybackPolicy = .automatic
        
        // Setup kontinuerlig loop
        setupContinuousLoop()
        
        // Observer for når video er klar
        setupPlayerObservers()
        
        // VIKTIG: Aktiver lyd eksplisitt
        ensureAudioIsEnabled()
        
        print("🔊 Video startet med lyd aktivert")
    }
    
    // MARK: - Ensure Audio Is Enabled
    private func ensureAudioIsEnabled() {
        // Dobbeltsjekk at audio session er aktiv
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                
                // Sikre at audio session er aktiv
                if !audioSession.isOtherAudioPlaying {
                    try audioSession.setActive(true)
                }
                
                // Route til høyttaler hvis mulig
                if audioSession.currentRoute.outputs.first?.portType != .builtInSpeaker {
                    try audioSession.overrideOutputAudioPort(.speaker)
                    print("🔊 Audio routet til høyttaler")
                }
                
                // Sjekk om player har lyd
                if let player = self.player {
                    player.volume = 1.0
                    player.isMuted = false
                    
                    // Sjekk om det faktisk er lydspor
                    if let currentItem = player.currentItem {
                        let audioTracks = currentItem.asset.tracks(withMediaType: .audio)
                        if audioTracks.isEmpty {
                            print("⚠️ ADVARSEL: Video har INGEN lydspor!")
                        } else {
                            print("🔊 Lyd-innstillinger bekreftet: \(audioTracks.count) lydspor, Volume = \(player.volume)")
                        }
                    }
                }
            } catch {
                print("⚠️ Kunne ikke aktivere lyd: \(error)")
            }
        }
    }
    
    // MARK: - Continuous Loop Setup
    private func setupContinuousLoop() {
        // Stop existing timer
        loopTimer?.invalidate()
        
        // Setup notification for when video ends
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        
        if let playerItem = player?.currentItem {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(videoDidEnd),
                name: .AVPlayerItemDidPlayToEndTime,
                object: playerItem
            )
        }
        
        // Backup timer for continuous monitoring
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkVideoLoop()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        loopTimer = timer
    }
    
    @objc private func videoDidEnd() {
        restartVideo()
    }
    
    private func checkVideoLoop() {
        guard let player = player,
              let currentItem = player.currentItem,
              currentItem.status == .readyToPlay else { return }
        
        let currentTime = player.currentTime()
        let duration = currentItem.duration
        
        if currentTime.seconds >= (duration.seconds - 0.1) && duration.seconds > 0 {
            restartVideo()
        }
    }
    
    private func restartVideo() {
        guard let player = player else { return }
        
        player.seek(to: CMTime.zero) { completed in
            if completed {
                player.play()
                // Sikre at lyd fortsatt er på
                player.volume = 1.0
                player.isMuted = false
            }
        }
    }
    
    // MARK: - Player Observers
    private func setupPlayerObservers() {
        guard let player = player else { return }
        
        playerStatusObserver = player.observe(\.status, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.handlePlayerStatusChange(player: player)
            }
        }
        
        if let currentItem = player.currentItem {
            playerItemStatusObserver = currentItem.observe(\.status, options: [.new]) { [weak self] item, _ in
                Task { @MainActor in
                    self?.handlePlayerItemStatusChange(item: item)
                }
            }
        }
    }
    
    private func handlePlayerStatusChange(player: AVPlayer) {
        switch player.status {
        case .readyToPlay:
            print("✅ Player klar - starter avspilling med lyd")
            player.play()
            player.volume = 1.0  // Sikre volum er på
            player.isMuted = false  // Sikre ikke muted
            isPlaying = true
            
        case .failed:
            print("❌ Player feilet: \(player.error?.localizedDescription ?? "Ukjent feil")")
            isPlaying = false
            
        case .unknown:
            print("⚠️ Player status ukjent")
            
        @unknown default:
            print("⚠️ Player status ukjent (default)")
        }
    }
    
    private func handlePlayerItemStatusChange(item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            print("✅ PlayerItem klar for avspilling")
            // Sjekk om video har lydspor
            let audioTracks = item.asset.tracks(withMediaType: .audio)
            if audioTracks.isEmpty {
                print("⚠️ Video har ingen lydspor")
            } else {
                print("🔊 Video har \(audioTracks.count) lydspor")
            }
            
        case .failed:
            print("❌ PlayerItem feilet: \(item.error?.localizedDescription ?? "Ukjent feil")")
            
        case .unknown:
            print("⚠️ PlayerItem status ukjent")
            
        @unknown default:
            print("⚠️ PlayerItem status ukjent (default)")
        }
    }
    
    // MARK: - Get Video URL - FORBEDRET
    private func getVideoURL(for filename: String) -> URL? {
        let nameWithoutExtension = filename.replacingOccurrences(of: ".mp4", with: "")
        
        print("🔍 Søker etter video: '\(nameWithoutExtension)'")
        
        // Sjekk documents directory først (for nye opptak)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let documentURL = documentsPath.appendingPathComponent("\(nameWithoutExtension).mp4")
        
        if FileManager.default.fileExists(atPath: documentURL.path) {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: documentURL.path)[.size] as? Int) ?? 0
            print("✅ Fant video i documents: \(nameWithoutExtension).mp4 (størrelse: \(fileSize) bytes)")
            return documentURL
        }
        
        // Sjekk bundle som backup
        if let bundleURL = Bundle.main.url(forResource: nameWithoutExtension, withExtension: "mp4") {
            print("✅ Fant video i bundle: \(nameWithoutExtension).mp4")
            return bundleURL
        }
        
        print("❌ Video ikke funnet: \(filename)")
        return nil
    }
    
    // MARK: - Control Methods
    func pauseVideo() {
        player?.pause()
        isPlaying = false
        print("⏸️ Video pauset")
    }
    
    func resumeVideo() {
        player?.play()
        player?.volume = 1.0
        player?.isMuted = false
        isPlaying = true
        print("▶️ Video gjenopptatt med lyd")
    }
    
    func stopVideo() {
        player?.pause()
        player?.seek(to: CMTime.zero)
        isPlaying = false
        print("⏹️ Video stoppet")
    }
    
    func setVolume(_ volume: Float) {
        player?.volume = volume
        self.volume = volume
        print("🔊 Volum satt til: \(volume)")
    }
    
    func toggleMute() {
        guard let player = player else { return }
        player.isMuted.toggle()
        print("🔇 Mute: \(player.isMuted)")
    }
    
    func completelyStopVideo() {
        print("🛑 Stopper video helt med loop cleanup")
        
        // Stop timer
        loopTimer?.invalidate()
        loopTimer = nil
        
        // Remove observers
        playerStatusObserver?.invalidate()
        playerStatusObserver = nil
        
        playerItemStatusObserver?.invalidate()
        playerItemStatusObserver = nil
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        
        // Stop and clear player
        player?.pause()
        player = nil
        
        // Reset state
        isPlaying = false
        currentContact = nil
        
        print("🧹 Video loop cleanup fullført")
    }
    
    // MARK: - Getters
    func getPlayer() -> AVPlayer? {
        return player
    }
    
    func getCurrentContact() -> Contact? {
        return currentContact
    }
    
    // MARK: - Video Exists Check
    func videoExists(for contact: Contact) -> Bool {
        guard !contact.instructionVideoURL.isEmpty else { return false }
        return getVideoURL(for: contact.instructionVideoURL) != nil
    }
}
