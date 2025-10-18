import SwiftUI
import AVFoundation

// FJERNET SimpleCameraManager - bruker RealCameraManager fra egen fil i stedet

// MARK: - ADD CONTACT VIEW - FIXED VERSION
struct AddContactView: View {
    @ObservedObject var contactManager: ContactManager
    @Environment(\.dismiss) private var dismiss
    
    // Contact fields
    @State private var name = ""
    @State private var phoneNumber = ""
    @State private var relationship = "Familie"
    
    // Video recording states
    @State private var showVideoStep = false
    @State private var showingSuccess = false
    @State private var showingPermissionAlert = false
    @State private var skipVideo = false
    
    // Keyboard håndtering
    @FocusState private var focusedField: Field?
    
    // Camera manager - REAL VERSION (hvis RealCameraManager ikke er tilgjengelig, bruk SimpleCameraManager)
    @StateObject private var cameraManager = RealCameraManager()
    
    let relationshipOptions = ["Familie", "Venn", "Pleier", "Nabo", "Datter", "Sønn", "Annet"]
    
    // Field enum for keyboard focus
    enum Field {
        case name, phone
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if showVideoStep {
                    // VIDEO RECORDING STEP
                    videoRecordingView
                } else {
                    // CONTACT INFO STEP
                    contactInfoView
                }
            }
            .navigationTitle(showVideoStep ? "📹 Ta opp video" : "➕ Ny Kontakt")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Avbryt") {
                        hideKeyboard()
                        cleanup()
                        dismiss()
                    }
                }
                
                if !showVideoStep {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Neste") {
                            hideKeyboard()
                            proceedToVideoStep()
                        }
                        .disabled(name.isEmpty || phoneNumber.isEmpty)
                        .font(.headline)
                        .fontWeight(.bold)
                    }
                }
            }
            .onTapGesture {
                hideKeyboard()
            }
        }
        .alert("✅ Kontakt Opprettet!", isPresented: $showingSuccess) {
            Button("Ferdig") {
                dismiss()
            }
        } message: {
            Text("\(name) er lagt til med\(cameraManager.hasValidVideo ? " instruksjonsvideo" : "")!")
        }
        .alert("📷 Kamera Tillatelse", isPresented: $showingPermissionAlert) {
            Button("Gå til Innstillinger") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Avbryt", role: .cancel) {
                showVideoStep = false
            }
        } message: {
            Text("DemensApp trenger tilgang til kameraet for å ta opp instruksjonsvideoer.")
        }
        .onDisappear {
            cleanup()
        }
    }
    
    // MARK: - Contact Info View
    private var contactInfoView: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 15) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Legg til ny kontakt")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Fyll ut informasjon og ta eventuelt opp video")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                // Form
                VStack(spacing: 25) {
                    // Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("👤 Fullt navn")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        TextField("F.eks. Anna Johansen", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                            .focused($focusedField, equals: .name)
                            .submitLabel(.next)
                            .autocorrectionDisabled(true)  // Fjerner autocorrect som kan forårsake treghet
                            .textInputAutocapitalization(.words)  // Kun stor forbokstav
                            .onSubmit {
                                focusedField = .phone
                            }
                    }
                    
                    // Phone field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("📞 Telefonnummer")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(spacing: 10) {
                            HStack {
                                Text("+47")
                                    .font(.title3)
                                    .foregroundColor(.gray)
                                    .padding(.leading, 12)
                                
                                TextField("123 45 678", text: $phoneNumber)
                                    .keyboardType(.phonePad)
                                    .font(.title3)
                                    .focused($focusedField, equals: .phone)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            
                            // Keyboard dismiss knapp for nummer-tastatur
                            if focusedField == .phone {
                                HStack {
                                    Spacer()
                                    Button("Ferdig med tall") {
                                        hideKeyboard()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .animation(.easeInOut(duration: 0.3), value: focusedField)
                            }
                        }
                    }
                    
                    // Relationship field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("❤️ Relasjon")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Picker("Relasjon", selection: $relationship) {
                            ForEach(relationshipOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(15)
                
                // Next step info
                VStack(alignment: .leading, spacing: 12) {
                    Text("📹 Neste steg: Video opptak (valgfritt)")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Ta opp en kort instruksjonsvideo")
                        Text("• Si hvem du er og hvorfor du ringer")
                        Text("• Kan hoppes over om ønskelig")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.orange.opacity(0.05))
                .cornerRadius(15)
            }
            .padding()
        }
    }
    
    // MARK: - Video Recording View - EKTE KAMERA VERSION
    private var videoRecordingView: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 10) {
                Text("📹 Video opptak")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("for \(name)")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .padding(.top)
            
            // Camera preview eller placeholder
            if cameraManager.isCameraReady {
                // EKTE KAMERA PREVIEW
                CameraPreviewView(cameraManager: cameraManager)
                    .frame(height: 300)
                    .cornerRadius(15)
                    .overlay(
                        // Recording indicator
                        VStack {
                            if cameraManager.isRecording {
                                HStack {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 12, height: 12)
                                        .scaleEffect(1.2)
                                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: cameraManager.isRecording)
                                    
                                    Text("REC")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.red)
                                    
                                    Text(formatTime(cameraManager.recordingDuration))
                                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                                        .foregroundColor(.red)
                                    
                                    Spacer()
                                }
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                                .padding(8)
                            }
                            Spacer()
                        }
                    )
            } else {
                // Placeholder hvis kamera ikke er klart
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 300)
                    .overlay(
                        VStack(spacing: 15) {
                            if let error = cameraManager.errorMessage {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 40))
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            } else {
                                ProgressView()
                                Text("Starter kamera...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    )
                    .cornerRadius(15)
            }
            
            // Record button
            Button(action: toggleRecording) {
                ZStack {
                    Circle()
                        .fill(cameraManager.isRecording ? Color.red : Color.white)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Circle()
                                .stroke(Color.red, lineWidth: 4)
                        )
                    
                    if cameraManager.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 60, height: 60)
                    }
                }
            }
            .disabled(cameraManager.hasValidVideo || !cameraManager.isCameraReady)
            
            // Status and action buttons
            VStack(spacing: 20) {
                if cameraManager.hasValidVideo && !cameraManager.isRecording {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Video tatt opp!")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
                
                HStack(spacing: 20) {
                    if cameraManager.hasValidVideo {
                        Button("Ta på nytt") {
                            cameraManager.clearRecording()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Button("Hopp over video") {
                        skipVideo = true
                        saveContactWithoutVideo()
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    
                    Button("💾 Lagre med video") {
                        saveContactWithVideo()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!cameraManager.hasValidVideo)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .onAppear {
            // Camera starter automatisk når RealCameraManager initialiseres
        }
        .onDisappear {
            cameraManager.stopSession()
        }
    }
    
    // MARK: - Keyboard hiding function
    private func hideKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    // MARK: - Actions
    private func proceedToVideoStep() {
        guard !name.isEmpty, !phoneNumber.isEmpty else { return }
        
        withAnimation {
            showVideoStep = true
        }
    }
    
    private func toggleRecording() {
        if cameraManager.isRecording {
            cameraManager.stopRecording()
        } else {
            let cleanName = name.lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "æ", with: "ae")
                .replacingOccurrences(of: "ø", with: "o")
                .replacingOccurrences(of: "å", with: "a")
            let fileName = "\(cleanName)_\(Int(Date().timeIntervalSince1970))_instruction"
            
            cameraManager.startRecording(fileName: fileName)
        }
    }
    
    private func saveContactWithVideo() {
        guard let fileName = cameraManager.recordedVideoFileName else {
            saveContactWithoutVideo()
            return
        }
        
        let formattedPhone = formatPhoneNumber(phoneNumber)
        
        let newContact = Contact(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            phoneNumber: formattedPhone,
            relationship: relationship,
            instructionVideoURL: fileName,
            isApproved: true,
            isMe: false
        )
        
        contactManager.addContact(newContact)
        
        print("✅ Kontakt med video opprettet: \(newContact.name)")
        print("📹 Video URL: \(fileName)")
        
        showingSuccess = true
    }
    
    private func saveContactWithoutVideo() {
        let formattedPhone = formatPhoneNumber(phoneNumber)
        
        let newContact = Contact(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            phoneNumber: formattedPhone,
            relationship: relationship,
            instructionVideoURL: "",
            isApproved: true,
            isMe: false
        )
        
        contactManager.addContact(newContact)
        
        print("✅ Kontakt opprettet uten video: \(newContact.name)")
        
        showingSuccess = true
    }
    
    private func formatPhoneNumber(_ phone: String) -> String {
        let cleanPhone = phone.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        
        if cleanPhone.count == 8 && cleanPhone.allSatisfy(\.isNumber) {
            return "+47 \(cleanPhone)"
        }
        
        return "+47 \(cleanPhone)"
    }
    
    private func cleanup() {
        cameraManager.stopSession()
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

#Preview {
    AddContactView(contactManager: ContactManager())
}
