import SwiftUI
import AVFoundation
import Photos

// REAL VIDEO RECORDING MANAGER - Faktisk kameraopptak
class RealVideoRecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration = 0
    @Published var videoURL: URL?
    @Published var isSetupComplete = false
    @Published var errorMessage: String?
    
    private var captureSession: AVCaptureSession?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var timer: Timer?
    
    override init() {
        super.init()
        checkPermissionsAndSetup()
    }
    
    // MARK: - Permissions & Setup
    private func checkPermissionsAndSetup() {
        // Check camera permission
        AVCaptureDevice.requestAccess(for: .video) { [weak self] videoGranted in
            guard videoGranted else {
                DispatchQueue.main.async {
                    self?.errorMessage = "Kamera-tilgang nektet. Gå til Innstillinger."
                }
                return
            }
            
            // Check microphone permission
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] audioGranted in
                guard audioGranted else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Mikrofon-tilgang nektet. Gå til Innstillinger."
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self?.setupCaptureSession()
                }
            }
        }
    }
    
    private func setupCaptureSession() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high
        
        // Setup video input (front camera for instruction videos)
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                        for: .video,
                                                        position: .front) else {
            errorMessage = "Finner ikke frontkamera"
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: frontCamera)
            
            if captureSession?.canAddInput(videoInput) == true {
                captureSession?.addInput(videoInput)
            }
            
            // Setup audio input
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession?.canAddInput(audioInput) == true {
                    captureSession?.addInput(audioInput)
                }
            }
            
            // Setup movie output
            movieOutput = AVCaptureMovieFileOutput()
            
            // Set max duration to 60 seconds
            movieOutput?.maxRecordedDuration = CMTime(seconds: 60, preferredTimescale: 1)
            
            if let movieOutput = movieOutput,
               captureSession?.canAddOutput(movieOutput) == true {
                captureSession?.addOutput(movieOutput)
                
                // Configure for best quality
                if let connection = movieOutput.connection(with: .video) {
                    if connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .auto
                    }
                }
            }
            
            // Create preview layer
            if let session = captureSession {
                videoPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
                videoPreviewLayer?.videoGravity = .resizeAspectFill
            }
            
            isSetupComplete = true
            print("✅ Kamera setup fullført")
            
        } catch {
            errorMessage = "Kunne ikke sette opp kamera: \(error.localizedDescription)"
            print("❌ Camera setup error: \(error)")
        }
    }
    
    // MARK: - Recording Controls
    func startRecording(for contact: Contact) {
        guard let movieOutput = movieOutput,
              !movieOutput.isRecording else { return }
        
        // Create unique filename
        let timestamp = Int(Date().timeIntervalSince1970)
        let cleanName = contact.name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "ø", with: "o")
            .replacingOccurrences(of: "å", with: "a")
        
        let fileName = "\(cleanName)_\(timestamp)_instruction.mp4"
        
        // Get documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask)[0]
        let outputURL = documentsPath.appendingPathComponent(fileName)
        
        // Remove existing file if any
        try? FileManager.default.removeItem(at: outputURL)
        
        // Start recording
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        
        // Start timer
        isRecording = true
        recordingDuration = 0
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.recordingDuration += 1
            
            // Auto-stop after 60 seconds
            if self?.recordingDuration ?? 0 >= 60 {
                self?.stopRecording()
            }
        }
        
        print("🎥 Starter opptak: \(fileName)")
    }
    
    func stopRecording() {
        movieOutput?.stopRecording()
        timer?.invalidate()
        timer = nil
        isRecording = false
        print("⏹ Stopper opptak")
    }
    
    func startCameraSession() {
        guard let session = captureSession,
              !session.isRunning else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }
    
    func stopCameraSession() {
        guard let session = captureSession,
              session.isRunning else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }
    
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        return videoPreviewLayer
    }
    
    // MARK: - Save to Photos (optional)
    func saveToPhotoLibrary() {
        guard let videoURL = videoURL else { return }
        
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else { return }
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            }) { success, error in
                if success {
                    print("✅ Video lagret til Bilder")
                } else if let error = error {
                    print("❌ Kunne ikke lagre til Bilder: \(error)")
                }
            }
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension RealVideoRecordingManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                   didFinishRecordingTo outputFileURL: URL,
                   from connections: [AVCaptureConnection],
                   error: Error?) {
        
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
            
            if let error = error {
                // Check if we have a valid file despite error
                if (error as NSError).code == -11810 {
                    // Recording stopped normally
                    self?.videoURL = outputFileURL
                    self?.verifyVideoFile(at: outputFileURL)
                } else {
                    self?.errorMessage = "Opptaksfeil: \(error.localizedDescription)"
                    print("❌ Recording error: \(error)")
                }
            } else {
                self?.videoURL = outputFileURL
                self?.verifyVideoFile(at: outputFileURL)
            }
        }
    }
    
    private func verifyVideoFile(at url: URL) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int ?? 0
            
            if fileSize > 10000 { // Minimum 10KB for valid video
                print("✅ Video lagret: \(url.lastPathComponent)")
                print("📊 Størrelse: \(fileSize / 1024) KB")
                
                // Verify it's playable - iOS compatible
                if #available(iOS 16.0, *) {
                    Task { @MainActor in
                        do {
                            let asset = AVURLAsset(url: url)
                            let playable = try await asset.load(.isPlayable)
                            print("▶️ Kan spilles av: \(playable)")
                            
                            if !playable {
                                self.errorMessage = "Video kan ikke spilles av. Prøv igjen."
                            }
                        } catch {
                            print("⚠️ Kunne ikke sjekke spillbarhet: \(error)")
                            self.errorMessage = "Kunne ikke verifisere video: \(error.localizedDescription)"
                        }
                    }
                } else {
                    // Fallback for iOS 15
                    let asset = AVAsset(url: url)
                    let playable = asset.isPlayable
                    print("▶️ Kan spilles av: \(playable)")
                    
                    if !playable {
                        errorMessage = "Video kan ikke spilles av. Prøv igjen."
                    }
                }
            } else {
                errorMessage = "Video for liten. Prøv igjen."
                print("❌ Video fil for liten: \(fileSize) bytes")
            }
        } catch {
            errorMessage = "Kunne ikke verifisere video: \(error.localizedDescription)"
            print("❌ Verification error: \(error)")
        }
    }
}
