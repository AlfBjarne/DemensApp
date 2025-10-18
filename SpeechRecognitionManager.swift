import Foundation
import Speech
import AVFoundation

class SpeechRecognitionManager: NSObject, ObservableObject {
    @Published var recognizedText = ""
    @Published var isListening = false
    @Published var isAvailable = false
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    
    override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "nb-NO"))
        speechRecognizer?.delegate = self
        requestPermissions()
    }
    
    private func requestPermissions() {
        // Be om stemmegjenkjenning tillatelse
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                // Be om mikrofon tillatelse (iOS 17+)
                AVAudioApplication.requestRecordPermission { micGranted in
                    DispatchQueue.main.async {
                        self?.isAvailable = status == .authorized && micGranted
                        print("🎤 Stemmegjenkjenning: \(status), Mikrofon: \(micGranted)")
                    }
                }
            }
        }
    }
    
    func startListening() {
        guard isAvailable else {
            print("❌ Stemmegjenkjenning ikke tilgjengelig")
            return
        }
        
        guard !isListening else {
            print("⚠️ Lytter allerede")
            return
        }
        
        print("🎤 Starter stemmegjenkjenning...")
        
        // Stopp eksisterende session
        stopListening()
        
        // Sett opp audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("❌ Audio session setup failed: \(error)")
            return
        }
        
        // Opprett recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("❌ Kunne ikke opprette recognition request")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Sett opp audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        // Forbered og start audio engine
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            print("❌ Audio engine start failed: \(error)")
            return
        }
        
        // Start gjenkjenning
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let result = result {
                    self.recognizedText = result.bestTranscription.formattedString
                    print("🗣️ Gjenkjent: '\(self.recognizedText)'")
                }
                
                if error != nil || result?.isFinal == true {
                    print("🔇 Stemmegjenkjenning session avsluttet")
                    self.stopListening()
                }
            }
        }
        
        isListening = true
        print("🎤 Stemmegjenkjenning aktiv")
    }
    
    func stopListening() {
        guard isListening else { return }
        
        print("🔇 Stopper stemmegjenkjenning...")
        
        // Stopp audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // Avslutt recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // Kanseller recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isListening = false
        
        // Deaktiver audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("❌ Audio session deactivation failed: \(error)")
        }
        
        print("🔇 Stemmegjenkjenning stoppet")
    }
    
    deinit {
        stopListening()
    }
}

// MARK: - SFSpeechRecognizerDelegate
extension SpeechRecognitionManager: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async {
            self.isAvailable = available
            print("🎤 Stemmegjenkjenning tilgjengelighet endret: \(available)")
        }
    }
}
