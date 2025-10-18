import SwiftUI
import AVFoundation

// MARK: - Working Video Recorder with Public Access
@MainActor
class WorkingVideoRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isSetupComplete = false
    @Published var recordingDuration = 0
    @Published var videoURL: URL?
    @Published var errorMessage: String?
    
    // CHANGED: Made public for access
    var captureSession: AVCaptureSession!
    var movieOutput: AVCaptureMovieFileOutput!
    var videoPreviewLayer: AVCaptureVideoPreviewLayer!
    private var timer: Timer?
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    // CHANGED: Made public for re-initialization
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupSession()
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Kamera tilgang nektet. Gå til Innstillinger > DemensApp > Kamera"
                    }
                }
            }
        default:
            errorMessage = "Kamera tilgang nektet. Gå til Innstillinger > DemensApp > Kamera"
        }
    }
    
    private func setupSession() {
        captureSession = AVCaptureSession()
        captureSession.beginConfiguration()
        
        // Video Quality
        if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }
        
        // Get front camera for selfie-style instruction videos
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                        for: .video,
                                                        position: .front) else {
            errorMessage = "Ingen frontkamera funnet"
            return
        }
        
        do {
            // Configure camera for best quality
            try videoDevice.lockForConfiguration()
            if videoDevice.isFocusModeSupported(.continuousAutoFocus) {
                videoDevice.focusMode = .continuousAutoFocus
            }
            videoDevice.unlockForConfiguration()
            
            // Add video input
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
            
            // Add audio input
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession.canAddInput(audioInput) {
                    captureSession.addInput(audioInput)
                }
            }
            
            // Setup movie output
            movieOutput = AVCaptureMovieFileOutput()
            movieOutput.maxRecordedDuration = CMTime(seconds: 60, preferredTimescale: 1)
            
            if captureSession.canAddOutput(movieOutput) {
                captureSession.addOutput(movieOutput)
                
                // Configure connection
                if let connection = movieOutput.connection(with: .video) {
                    if connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .auto
                    }
                    // Set video orientation - iOS 17+ compatible
                    if #available(iOS 17.0, *) {
                        connection.videoRotationAngle = 0 // Portrait
                    } else {
                        connection.videoOrientation = .portrait
                    }
                }
            }
            
            // Create preview layer
            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            videoPreviewLayer.videoGravity = .resizeAspectFill
            
            captureSession.commitConfiguration()
            
            // Start session on background queue
            if let session = captureSession {
                DispatchQueue.global(qos: .userInitiated).async {
                    session.startRunning()
                    DispatchQueue.main.async { [weak self] in
                        self?.isSetupComplete = true
                        print("✅ Kamera klar for opptak")
                    }
                }
            }
            
        } catch {
            errorMessage = "Kunne ikke sette opp kamera: \(error.localizedDescription)"
            captureSession.commitConfiguration()
            print("❌ Camera setup error: \(error)")
        }
    }
    
    func startRecording(fileName: String) {
        guard !movieOutput.isRecording else { return }
        
        // Create output URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask)[0]
        let outputURL = documentsPath.appendingPathComponent("\(fileName).mp4")
        
        // Remove old file if exists
        try? FileManager.default.removeItem(at: outputURL)
        
        // Configure output settings - ONLY codec and compression properties are allowed
        if movieOutput.availableVideoCodecTypes.contains(.h264) {
            if let connection = movieOutput.connection(with: .video) {
                let outputSettings = [
                    AVVideoCodecKey: AVVideoCodecType.h264
                ] as [String: Any]
                movieOutput.setOutputSettings(outputSettings, for: connection)
            }
        }
        
        // Start recording
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        isRecording = true
        recordingDuration = 0
        
        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.recordingDuration += 1
                if self.recordingDuration >= 60 {
                    self.stopRecording()
                }
            }
        }
        
        print("🎥 Starter opptak: \(fileName)")
    }
    
    func stopRecording() {
        if movieOutput?.isRecording == true {
            movieOutput.stopRecording()
        }
        timer?.invalidate()
        timer = nil
        isRecording = false
        print("⏹ Stopper opptak")
    }
    
    func cleanup() {
        timer?.invalidate()
        timer = nil
        
        if let session = captureSession, session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.stopRunning()
            }
        }
        print("🧹 Cleanup completed")
    }
    
    deinit {
        // Cleanup will be called from onDisappear
        timer?.invalidate()
    }
}

// MARK: - Recording Delegate
extension WorkingVideoRecorder: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                   didFinishRecordingTo outputFileURL: URL,
                   from connections: [AVCaptureConnection],
                   error: Error?) {
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isRecording = false
            
            if let error = error {
                let nsError = error as NSError
                if nsError.code == -11810 {
                    // Recording stopped normally
                    self.videoURL = outputFileURL
                    self.verifyVideo(at: outputFileURL)
                } else {
                    self.errorMessage = "Opptak feilet: \(error.localizedDescription)"
                    print("❌ Recording error: \(error)")
                }
            } else {
                // Success
                self.videoURL = outputFileURL
                self.verifyVideo(at: outputFileURL)
            }
        }
    }
    
    private func verifyVideo(at url: URL) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int ?? 0
            
            print("✅ Video lagret: \(url.lastPathComponent)")
            print("📊 Størrelse: \(fileSize / 1024) KB")
            
            // Verify it's playable - iOS 16+ compatible
            if #available(iOS 16.0, *) {
                Task { [weak self] in
                    guard let self = self else { return }
                    do {
                        let asset = AVURLAsset(url: url)
                        let isPlayable = try await asset.load(.isPlayable)
                        if isPlayable {
                            print("▶️ Video kan spilles av")
                        } else {
                            await MainActor.run {
                                self.errorMessage = "Video kan ikke spilles av. Prøv igjen."
                            }
                            print("❌ Video ikke spillbar")
                        }
                    } catch {
                        print("⚠️ Kunne ikke sjekke spillbarhet: \(error)")
                    }
                }
            } else {
                // Fallback for iOS 15 and earlier
                let asset = AVAsset(url: url)
                if asset.isPlayable {
                    print("▶️ Video kan spilles av")
                } else {
                    errorMessage = "Video kan ikke spilles av. Prøv igjen."
                    print("❌ Video ikke spillbar")
                }
            }
            
            if fileSize < 10000 {
                errorMessage = "Video for kort. Ta opp minst 5 sekunder."
            }
        } catch {
            errorMessage = "Kunne ikke verifisere video: \(error.localizedDescription)"
            print("❌ Verification error: \(error)")
        }
    }
}

// MARK: - Camera Preview Layer View
struct CameraPreviewLayer: UIViewRepresentable {
    let recorder: WorkingVideoRecorder
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black
        
        // Add preview layer if available
        if let previewLayer = recorder.videoPreviewLayer {
            previewLayer.frame = view.bounds
            view.layer.addSublayer(previewLayer)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update preview layer frame safely
        if let previewLayer = recorder.videoPreviewLayer {
            DispatchQueue.main.async {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                
                let bounds = uiView.bounds
                // Check for valid bounds to avoid NaN errors
                if bounds.width > 0 && bounds.height > 0 &&
                   bounds.width.isFinite && bounds.height.isFinite {
                    previewLayer.frame = bounds
                }
                
                CATransaction.commit()
            }
        }
    }
}

// MARK: - Main Video Recording View
struct VideoRecordingView: View {
    let contact: Contact
    @ObservedObject var contactManager: ContactManager
    @StateObject private var recorder = WorkingVideoRecorder()
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingSaveAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Camera preview background
                if recorder.isSetupComplete {
                    CameraPreviewLayer(recorder: recorder)
                        .ignoresSafeArea()
                } else {
                    Color.black
                        .ignoresSafeArea()
                        .overlay(loadingView)
                }
                
                // UI Overlay
                VStack {
                    // Top bar
                    topBar
                    
                    Spacer()
                    
                    // Center content
                    if recorder.isRecording {
                        recordingIndicator
                    } else if !recorder.isRecording && recorder.videoURL == nil {
                        instructionsView
                    }
                    
                    Spacer()
                    
                    // Bottom controls
                    bottomControls
                }
            }
            .navigationBarHidden(true)
            .alert("Video lagret!", isPresented: $showingSaveAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Instruksjonsvideo for \(contact.name) er klar!")
            }
            .alert("Feil", isPresented: .constant(recorder.errorMessage != nil)) {
                Button("OK") {
                    recorder.errorMessage = nil
                }
                Button("Prøv igjen") {
                    recorder.errorMessage = nil
                    recorder.cleanup()
                    recorder.checkPermissions()
                }
            } message: {
                Text(recorder.errorMessage ?? "")
            }
        }
        .onDisappear {
            recorder.cleanup()
        }
    }
    
    // MARK: - View Components
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            Text("Starter kamera...")
                .foregroundColor(.white)
                .font(.headline)
        }
    }
    
    private var topBar: some View {
        HStack {
            Button("Avbryt") {
                recorder.cleanup()
                dismiss()
            }
            .foregroundColor(.white)
            .padding()
            
            Spacer()
            
            VStack(spacing: 4) {
                Text("Video for")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                Text(contact.name)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Balance spacing
            Color.clear
                .frame(width: 60)
        }
        .background(Color.black.opacity(0.6))
    }
    
    private var recordingIndicator: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .scaleEffect(1.2)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                              value: recorder.isRecording)
                
                Text("OPPTAR")
                    .foregroundColor(.white)
                    .font(.headline)
                
                Text(formatTime(recorder.recordingDuration))
                    .foregroundColor(.white)
                    .font(.system(.title3, design: .monospaced))
            }
            .padding()
            .background(Color.red.opacity(0.8))
            .cornerRadius(20)
            
            Text("Maks 60 sekunder")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private var instructionsView: some View {
        VStack(spacing: 10) {
            Text("📹 INSTRUKSJONSVIDEO")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 8) {
                Label("Si hvem du er", systemImage: "person.fill")
                Label("Forklar hvorfor du ringer", systemImage: "phone.fill")
                Label("Hold det kort (15-30 sek)", systemImage: "timer")
                Label("Snakk tydelig", systemImage: "waveform")
            }
            .font(.subheadline)
            .foregroundColor(.white)
        }
        .padding()
        .background(Color.black.opacity(0.6))
        .cornerRadius(15)
        .padding(.horizontal)
    }
    
    private var bottomControls: some View {
        VStack(spacing: 20) {
            // Record button
            Button(action: handleRecordButton) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 75, height: 75)
                    
                    if recorder.isRecording {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red)
                            .frame(width: 30, height: 30)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 65, height: 65)
                    }
                }
            }
            
            // Action buttons after recording
            if recorder.videoURL != nil && !recorder.isRecording {
                HStack(spacing: 30) {
                    Button(action: {
                        recorder.videoURL = nil
                    }) {
                        Label("Ta på nytt", systemImage: "arrow.clockwise")
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(20)
                    }
                    
                    Button(action: saveVideo) {
                        Label("Lagre", systemImage: "checkmark.circle.fill")
                            .padding(.horizontal, 25)
                            .padding(.vertical, 10)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .cornerRadius(20)
                    }
                }
            }
        }
        .padding(.bottom, 50)
    }
    
    // MARK: - Actions
    
    private func handleRecordButton() {
        if recorder.isRecording {
            recorder.stopRecording()
        } else if recorder.videoURL == nil {
            // Start recording directly without countdown
            startRecording()
        }
    }
    
    private func startRecording() {
        let cleanName = contact.name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "ø", with: "o")
            .replacingOccurrences(of: "å", with: "a")
        
        let fileName = "\(cleanName)_\(Int(Date().timeIntervalSince1970))_instruction"
        recorder.startRecording(fileName: fileName)
    }
    
    private func saveVideo() {
        guard let videoURL = recorder.videoURL else { return }
        
        let fileName = videoURL.deletingPathExtension().lastPathComponent
        contactManager.updateContactWithVideo(contact, videoFileName: fileName)
        
        print("✅ Video lagret for kontakt: \(contact.name)")
        print("📁 Filnavn: \(fileName)")
        
        showingSaveAlert = true
    }
    
    private func formatTime(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
