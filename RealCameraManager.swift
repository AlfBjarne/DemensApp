import SwiftUI
import AVFoundation

// MARK: - REAL CAMERA MANAGER - Faktisk video opptak
class RealCameraManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration = 0
    @Published var isCameraReady = false
    @Published var hasValidVideo = false
    @Published var recordedVideoURL: URL?
    @Published var recordedVideoFileName: String?
    @Published var errorMessage: String?
    
    private var captureSession: AVCaptureSession?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var timer: Timer?
    
    override init() {
        super.init()
        checkCameraPermissions()
    }
    
    // MARK: - Camera Permissions
    private func checkCameraPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupCamera()
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Kamera tilgang nektet"
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = "Kamera tilgang nektet. Gå til Innstillinger for å aktivere."
        @unknown default:
            errorMessage = "Ukjent kamera status"
        }
        
        // Check microphone permissions
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        default:
            break
        }
    }
    
    // MARK: - Camera Setup
    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high
        
        // Setup video input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            errorMessage = "Ingen front-kamera tilgjengelig"
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: camera)
            if captureSession?.canAddInput(videoInput) == true {
                captureSession?.addInput(videoInput)
            }
            
            // Setup audio input med forbedret lydkvalitet
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession?.canAddInput(audioInput) == true {
                    captureSession?.addInput(audioInput)
                    print("🎤 Mikrofon lagt til for opptak")
                } else {
                    print("⚠️ Kunne ikke legge til mikrofon")
                }
            } else {
                print("⚠️ Ingen mikrofon tilgjengelig")
            }
            
            // Setup movie output
            movieOutput = AVCaptureMovieFileOutput()
            if let movieOutput = movieOutput, captureSession?.canAddOutput(movieOutput) == true {
                captureSession?.addOutput(movieOutput)
                
                // Configure for better quality
                if let connection = movieOutput.connection(with: .video) {
                    if connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .auto
                    }
                }
            }
            
            // Start session
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
                DispatchQueue.main.async {
                    self?.isCameraReady = true
                    print("✅ Kamera klar for opptak")
                }
            }
            
        } catch {
            errorMessage = "Kunne ikke sette opp kamera: \(error.localizedDescription)"
            print("❌ Camera setup error: \(error)")
        }
    }
    
    // MARK: - Recording Functions
    func startRecording(fileName: String) {
        guard let movieOutput = movieOutput, !isRecording else { return }
        
        recordedVideoFileName = fileName
        
        // Create output URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputURL = documentsPath.appendingPathComponent("\(fileName).mp4")
        
        // Remove existing file if any
        try? FileManager.default.removeItem(at: outputURL)
        
        // Start recording
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        
        // Start timer
        isRecording = true
        recordingDuration = 0
        hasValidVideo = false
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.recordingDuration += 1
            
            // Auto-stop after 60 seconds
            if self?.recordingDuration ?? 0 >= 60 {
                self?.stopRecording()
            }
        }
        
        print("🎥 Starter EKTE video opptak: \(fileName)")
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        movieOutput?.stopRecording()
        timer?.invalidate()
        timer = nil
        isRecording = false
        
        print("🛑 Stopper video opptak")
    }
    
    func clearRecording() {
        if let url = recordedVideoURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordedVideoURL = nil
        recordedVideoFileName = nil
        hasValidVideo = false
        recordingDuration = 0
        errorMessage = nil
    }
    
    func stopSession() {
        captureSession?.stopRunning()
        timer?.invalidate()
        timer = nil
    }
    
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        guard let session = captureSession else { return nil }
        
        if videoPreviewLayer == nil {
            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
            videoPreviewLayer?.videoGravity = .resizeAspectFill
        }
        return videoPreviewLayer
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension RealCameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let error = error {
                // Check if error is just interruption (which creates valid file)
                let nsError = error as NSError
                if nsError.domain == AVFoundationErrorDomain &&
                   nsError.code == AVError.Code.maximumDurationReached.rawValue {
                    // This is OK - max duration reached
                    self.handleSuccessfulRecording(outputFileURL)
                } else if FileManager.default.fileExists(atPath: outputFileURL.path) {
                    // File exists despite error - probably OK
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)[.size] as? Int) ?? 0
                    if fileSize > 10000 { // More than 10KB
                        print("⚠️ Video saved despite error, size: \(fileSize) bytes")
                        self.handleSuccessfulRecording(outputFileURL)
                    } else {
                        self.errorMessage = "Video for kort eller ødelagt"
                        print("❌ Video recording error: \(error)")
                    }
                } else {
                    self.errorMessage = "Opptak feilet: \(error.localizedDescription)"
                    print("❌ Video recording error: \(error)")
                }
            } else {
                // Success
                self.handleSuccessfulRecording(outputFileURL)
            }
            
            self.isRecording = false
        }
    }
    
    private func handleSuccessfulRecording(_ url: URL) {
        recordedVideoURL = url
        hasValidVideo = true
        
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int {
            print("✅ Video lagret: \(url.lastPathComponent) (\(fileSize) bytes)")
            
            // Verify the video can be played
            let asset = AVAsset(url: url)
            if asset.isPlayable {
                print("✅ Video er spillbar")
            } else {
                print("⚠️ Video kan ikke spilles av")
                errorMessage = "Video kan ikke spilles av"
            }
        }
    }
}

// MARK: - Camera Preview View
struct CameraPreviewView: UIViewRepresentable {
    let cameraManager: RealCameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        DispatchQueue.main.async {
            if let previewLayer = cameraManager.getPreviewLayer() {
                previewLayer.frame = view.bounds
                view.layer.addSublayer(previewLayer)
            }
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            if let previewLayer = cameraManager.getPreviewLayer() {
                previewLayer.frame = uiView.bounds
            }
        }
    }
}

// MARK: - Simple Camera View for Testing
struct SimpleCameraView: View {
    @StateObject private var cameraManager = RealCameraManager()
    @State private var showingAlert = false
    
    var body: some View {
        VStack {
            if cameraManager.isCameraReady {
                CameraPreviewView(cameraManager: cameraManager)
                    .frame(height: 400)
                    .cornerRadius(15)
                    .overlay(
                        recordingOverlay
                    )
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 400)
                    .cornerRadius(15)
                    .overlay(
                        VStack {
                            ProgressView()
                            Text("Starter kamera...")
                        }
                    )
            }
            
            // Controls
            VStack(spacing: 20) {
                if cameraManager.isRecording {
                    Text("Opptar: \(formatTime(cameraManager.recordingDuration))")
                        .font(.headline)
                        .foregroundColor(.red)
                }
                
                Button(action: toggleRecording) {
                    Circle()
                        .fill(cameraManager.isRecording ? Color.red : Color.white)
                        .frame(width: 70, height: 70)
                        .overlay(
                            Circle()
                                .stroke(Color.red, lineWidth: 3)
                        )
                        .overlay(
                            cameraManager.isRecording ?
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 25, height: 25)
                                .cornerRadius(4) :
                            nil
                        )
                }
                
                if let error = cameraManager.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                if cameraManager.hasValidVideo {
                    Text("✅ Video lagret!")
                        .foregroundColor(.green)
                }
            }
            .padding()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
    }
    
    private var recordingOverlay: some View {
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
                    
                    Spacer()
                }
                .padding(8)
            }
            Spacer()
        }
    }
    
    private func toggleRecording() {
        if cameraManager.isRecording {
            cameraManager.stopRecording()
        } else {
            let fileName = "test_video_\(Int(Date().timeIntervalSince1970))"
            cameraManager.startRecording(fileName: fileName)
        }
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

#Preview {
    SimpleCameraView()
}
