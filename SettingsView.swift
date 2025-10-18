import SwiftUI
import AVFoundation

struct SettingsView: View {
    @ObservedObject var contactManager: ContactManager
    @Environment(\.dismiss) private var dismiss
    @State private var microphoneEnabled = true
    @State private var callKitEnabled = true
    @State private var videoAutoplay = true
    @State private var speechSensitivity = 0.5
    @State private var fontSize: Double = 16
    @State private var showingSyncStatus = false
    @State private var syncStatusMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                // MARK: - iCloud Synkronisering
                Section("☁️ iCloud Synkronisering") {
                    Toggle("Synkroniser kontakter mellom enheter", isOn: $contactManager.iCloudSyncEnabled)
                        .onChange(of: contactManager.iCloudSyncEnabled) { _, enabled in
                            if enabled {
                                print("☁️ iCloud sync aktivert")
                                contactManager.syncWithiCloud()
                                syncStatusMessage = "✅ iCloud synkronisering aktivert"
                                showingSyncStatus = true
                                
                                // Skjul melding etter 3 sekunder
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    showingSyncStatus = false
                                }
                            } else {
                                print("☁️ iCloud sync deaktivert")
                                syncStatusMessage = "⛔ iCloud synkronisering deaktivert"
                                showingSyncStatus = true
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    showingSyncStatus = false
                                }
                            }
                        }
                    
                    if contactManager.iCloudSyncEnabled {
                        HStack {
                            Image(systemName: "checkmark.icloud.fill")
                                .foregroundColor(.green)
                            Text("iCloud aktiv")
                                .foregroundColor(.green)
                            Spacer()
                            Text("\(contactManager.contacts.count) kontakter")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Button(action: {
                            contactManager.loadFromiCloud()
                            syncStatusMessage = "⬇️ Laster fra iCloud..."
                            showingSyncStatus = true
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                syncStatusMessage = "✅ Oppdatert fra iCloud"
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showingSyncStatus = false
                                }
                            }
                        }) {
                            Label("Last ned fra iCloud", systemImage: "icloud.and.arrow.down")
                        }
                        
                        Button(action: {
                            contactManager.syncWithiCloud()
                            syncStatusMessage = "⬆️ Laster opp til iCloud..."
                            showingSyncStatus = true
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                syncStatusMessage = "✅ Lastet opp til iCloud"
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showingSyncStatus = false
                                }
                            }
                        }) {
                            Label("Last opp til iCloud", systemImage: "icloud.and.arrow.up")
                        }
                        .foregroundColor(.orange)
                    }
                    
                    if showingSyncStatus {
                        Text(syncStatusMessage)
                            .font(.caption)
                            .foregroundColor(.blue)
                            .transition(.opacity)
                    }
                    
                    Text("Kontakter synkroniseres automatisk mellom iPhone og iPad når iCloud er aktivert. Videoer synkroniseres ikke.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // MARK: - Audio/Video Innstillinger
                Section("🎤 Lyd og Video") {
                    Toggle("Mikrofon aktivert", isOn: $microphoneEnabled)
                        .onChange(of: microphoneEnabled) { _, newValue in
                            if newValue {
                                requestMicrophonePermission()
                            }
                        }
                    
                    Toggle("Video autostart", isOn: $videoAutoplay)
                    
                    VStack(alignment: .leading) {
                        Text("Stemmegjenkjenning følsomhet")
                        Slider(value: $speechSensitivity, in: 0...1)
                        HStack {
                            Text("Lav")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Høy")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // MARK: - Samtale Innstillinger
                Section("📞 Samtaler") {
                    Toggle("CallKit aktivert", isOn: $callKitEnabled)
                    
                    VStack(alignment: .leading) {
                        Text("Auto-svar ord:")
                        Text("\"Hallo\", \"Hei\", \"Ja\"")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // MARK: - Display Innstillinger
                Section("📱 Visning") {
                    VStack(alignment: .leading) {
                        Text("Tekststørrelse")
                        Slider(value: $fontSize, in: 12...24, step: 1)
                        Text("Størrelse: \(Int(fontSize))pt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // MARK: - Sikkerhet
                Section("🔐 Sikkerhet og Personvern") {
                    VStack(alignment: .leading) {
                        Text("Mikrofon tillatelse")
                        Button("Sjekk tillatelse") {
                            checkMicrophonePermission()
                        }
                        .font(.caption)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Data lagring")
                        Text("Kontakter lagres i iCloud når aktivert")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Videoer lagres kun lokalt på enheten")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // MARK: - Om Appen
                Section("ℹ️ Om DemensApp") {
                    HStack {
                        Text("Versjon")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Bygget")
                        Spacer()
                        Text("August 2025")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Enhet")
                        Spacer()
                        Text(UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad")
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Tilbakestill alle innstillinger") {
                        resetAllSettings()
                    }
                    .foregroundColor(.red)
                }
                
                // MARK: - Test Seksjon
                Section("🧪 Test og Feilsøking") {
                    Button("Test stemmegjenkjenning") {
                        testSpeechRecognition()
                    }
                    
                    Button("Test video avspilling") {
                        testVideoPlayback()
                    }
                    
                    Button("Test CallKit") {
                        testCallKit()
                    }
                    
                    Button("Sjekk iCloud status") {
                        checkiCloudStatus()
                    }
                    
                    Button("Rydd opp ødelagte videoer") {
                        contactManager.cleanupAndFixVideos()
                    }
                    .foregroundColor(.orange)
                }
            }
            .navigationTitle("Innstillinger")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Ferdig") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Functions
    private func requestMicrophonePermission() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    print("🎤 Mikrofon tillatelse gitt")
                } else {
                    print("❌ Mikrofon tillatelse nektet")
                    microphoneEnabled = false
                }
            }
        }
    }
    
    private func checkMicrophonePermission() {
        let status = AVAudioApplication.shared.recordPermission
        switch status {
        case .granted:
            print("✅ Mikrofon tillatelse: Gitt")
        case .denied:
            print("❌ Mikrofon tillatelse: Nektet")
        case .undetermined:
            print("❓ Mikrofon tillatelse: Ikke bestemt")
            requestMicrophonePermission()
        @unknown default:
            print("❓ Mikrofon tillatelse: Ukjent status")
        }
    }
    
    private func resetAllSettings() {
        microphoneEnabled = true
        callKitEnabled = true
        videoAutoplay = true
        speechSensitivity = 0.5
        fontSize = 16
        contactManager.iCloudSyncEnabled = false
        print("🔄 Alle innstillinger tilbakestilt")
    }
    
    private func testSpeechRecognition() {
        print("🧪 Testing stemmegjenkjenning...")
    }
    
    private func testVideoPlayback() {
        print("🧪 Testing video avspilling...")
    }
    
    private func testCallKit() {
        print("🧪 Testing CallKit...")
    }
    
    private func checkiCloudStatus() {
        print("\n☁️ === iCloud Status ===")
        print("☁️ Sync aktivert: \(contactManager.iCloudSyncEnabled)")
        print("☁️ Antall kontakter lokalt: \(contactManager.contacts.count)")
        
        let deviceType = UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad"
        print("📱 Enhet: \(deviceType)")
        
        if let myContact = contactManager.getMyContact() {
            print("👤 Denne enheten tilhører: \(myContact.name)")
        }
        
        print("📹 Kontakter med video:")
        for contact in contactManager.contacts {
            if !contact.instructionVideoURL.isEmpty {
                print("  ✅ \(contact.name): \(contact.instructionVideoURL)")
            }
        }
        
        print("========================\n")
        
        // Prøv å laste fra iCloud
        contactManager.loadFromiCloud()
    }
}

// Preview
#Preview {
    SettingsView(contactManager: ContactManager())
}
