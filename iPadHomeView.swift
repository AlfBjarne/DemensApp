import SwiftUI
import AVKit

struct iPadHomeView: View {
    @EnvironmentObject var contactManager: ContactManager  // Bruker Environment
    @StateObject private var videoManager = VideoManager()
    @StateObject private var videoCallSimulator = VideoCallSimulator()
    @StateObject private var agoraManager: AgoraVideoCallManager
    
    @State private var currentTime = Date()
    @State private var showIncomingVideoCall = false
    @State private var showOutgoingCall = false
    @State private var listeningTimer: Timer?
    @State private var clockTimer: Timer?
    @State private var incomingCallContact: Contact?
    @State private var outgoingCallContact: Contact?
    @State private var selectedVideoContact: Contact?
    @State private var showPhoneInterface = false
    @State private var showingTestCall = false
    @State private var isConnectingCall = false
    
    // COLORS
    private let backgroundColor = Color(red: 0.95, green: 0.97, blue: 1.0)
    private let timeColor = Color(red: 0.2, green: 0.3, blue: 0.6)
    private let dateColor = Color(red: 0.4, green: 0.5, blue: 0.7)
    
    init() {
        let tempVideoManager = VideoManager()
        let tempCallViewModel = CallViewModel(contact: Contact(name: "", phoneNumber: "", relationship: ""))
        _agoraManager = StateObject(wrappedValue: AgoraVideoCallManager(videoManager: tempVideoManager, callViewModel: tempCallViewModel))
    }
    
    // MARK: - Outgoing Call View
    private var outgoingCallView: some View {
        VStack {
            if let contact = outgoingCallContact {
                VStack(spacing: 40) {
                    Spacer()
                    
                    VStack(spacing: 30) {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 150, height: 150)
                            .overlay(
                                Text(String(contact.name.first ?? "?"))
                                    .font(.system(size: 70, weight: .bold))
                                    .foregroundColor(.blue)
                            )
                            .scaleEffect(isConnectingCall ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isConnectingCall)
                        
                        Text(isConnectingCall ? "Ringer..." : agoraManager.isInCall ? "Tilkoblet!" : "Venter...")
                            .font(.system(size: 35, weight: .medium))
                            .foregroundColor(agoraManager.isInCall ? .green : isConnectingCall ? .gray : .orange)
                        
                        VStack(spacing: 15) {
                            Text(contact.name)
                                .font(.system(size: 50, weight: .bold))
                                .foregroundColor(timeColor)
                            
                            Text(contact.relationship)
                                .font(.system(size: 30, weight: .medium))
                                .foregroundColor(dateColor)
                            
                            Text(contact.phoneNumber)
                                .font(.system(size: 25, weight: .light, design: .monospaced))
                                .foregroundColor(dateColor.opacity(0.8))
                            
                            if let myContact = contactManager.getMyContact() {
                                Text("Fra: \(myContact.name)")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        VStack(spacing: 10) {
                            Text("Status: \(agoraManager.getConnectionStateDescription())")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            if agoraManager.remoteUserID > 0 {
                                Text("✅ Tilkoblet (UID: \(agoraManager.remoteUserID))")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                            }
                            
                            if agoraManager.isInCall {
                                Text("⏱️ Varighet: \(agoraManager.formatCallDuration())")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 60) {
                        Button(action: { agoraManager.forceResetConnection() }) {
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 35))
                                            .foregroundColor(.white)
                                    )
                                
                                Text("Reset")
                                    .font(.title3)
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        Button(action: endOutgoingCall) {
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 100, height: 100)
                                    .overlay(
                                        Image(systemName: "phone.down.fill")
                                            .font(.system(size: 45))
                                            .foregroundColor(.white)
                                    )
                                    .shadow(color: Color.red.opacity(0.5), radius: 15)
                                
                                Text("Avslutt")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.bottom, 60)
                }
                .padding(40)
            }
        }
        .background(backgroundColor)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundColor
                    .ignoresSafeArea()
                
                if showOutgoingCall {
                    outgoingCallView
                } else {
                    VStack(spacing: 60) {
                        Spacer()
                        mainDateTimeDisplay
                        Spacer()
                    }
                    .padding(40)
                    
                    phoneCornerView(geometry: geometry)
                    connectionStatusView
                }
            }
        }
        .fullScreenCover(isPresented: $showIncomingVideoCall) {
            IncomingVideoCallView(
                simulator: videoCallSimulator,
                videoManager: videoManager,
                agoraManager: agoraManager
            )
        }
        .sheet(isPresented: $showPhoneInterface) {
            // RETTET: Pass contactManager som parameter
            PhoneInterfaceView(contactManager: contactManager) { contact in
                startOutgoingCall(to: contact)
            }
        }
        .alert("Ring til...", isPresented: $showingTestCall) {
            Button("Avbryt", role: .cancel) { }
            ForEach(contactManager.getContactsToCall().prefix(4)) { contact in
                Button("Ring \(contact.name)") {
                    startOutgoingCall(to: contact)
                }
            }
        } message: {
            Text("Velg hvem du vil ringe til:")
        }
        .onAppear {
            setupTimers()
            setupAgoraListening()
            selectVideoContact()
        }
        .onDisappear {
            cleanupTimers()
        }
        .onChange(of: agoraManager.remoteUserID) { _, newValue in
            handleRemoteUserJoined(uid: newValue)
        }
    }
    
    // MARK: - Main Date/Time Display
    private var mainDateTimeDisplay: some View {
        VStack(spacing: 40) {
            Text(formattedDateTimeString)
                .font(.system(size: 85, weight: .medium, design: .rounded))
                .foregroundColor(timeColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            Text(currentTime.timeString)
                .font(.system(size: 140, weight: .bold, design: .monospaced))
                .foregroundColor(timeColor)
        }
    }
    
    private var formattedDateTimeString: String {
        let weekday = currentTime.weekdayName
        let timeOfDay = currentTime.timeOfDay.lowercased()
        let day = currentTime.day
        let month = currentTime.monthName.lowercased()
        let year = currentTime.yearString
        
        return "\(weekday) \(timeOfDay)\n\(day). \(month) \(year)"
    }
    
    private var connectionStatusView: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(agoraManager.isInCall ? Color.green : agoraManager.isConnecting ? Color.orange : Color.gray)
                            .frame(width: 12, height: 12)
                        
                        Text(agoraManager.getConnectionStateDescription())
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    if agoraManager.remoteUserID > 0 {
                        Text("📱 iPhone tilkoblet")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                    } else {
                        Text("📡 Lytter etter anrop...")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.7))
                )
                .padding(.leading, 30)
                .padding(.top, 40)
                
                Spacer()
            }
            Spacer()
        }
    }
    
    private func phoneCornerView(geometry: GeometryProxy) -> some View {
        VStack {
            Spacer()
            HStack {
                VStack(spacing: 15) {
                    VStack(spacing: 20) {
                        Text("📞 TELEFON")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Button(action: openPhoneInterface) {
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 100, height: 100)
                                    .overlay(
                                        Image(systemName: "phone.fill")
                                            .font(.system(size: 45))
                                            .foregroundColor(.white)
                                    )
                                    .shadow(color: Color.green.opacity(0.5), radius: 15)
                                    .scaleEffect(1.05)
                                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: currentTime)
                                
                                Text("RING")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        VStack(spacing: 5) {
                            if let myContact = contactManager.getMyContact() {
                                Text(myContact.name)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Text("Klar til å ringe")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            } else {
                                Text("Ingen eier satt")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            
                            Text("Trykk for å ringe")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(25)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.8))
                            .shadow(color: Color.black.opacity(0.3), radius: 15)
                    )
                }
                .padding(.leading, 30)
                .padding(.bottom, 40)
                
                Spacer()
            }
        }
    }
    
    // MARK: - Setup Functions
    private func setupTimers() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            currentTime = Date()
        }
    }
    
    private func cleanupTimers() {
        clockTimer?.invalidate()
        clockTimer = nil
        listeningTimer?.invalidate()
        listeningTimer = nil
    }
    
    private func setupAgoraListening() {
        print("📱 iPad pauseside starter Agora lytting...")
        
        let channelName = "test_1308"
        agoraManager.prepareTestCallAsReceiver(channelName: channelName)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.agoraManager.joinWaitingRoom(channelName: channelName)
        }
        
        print("📱 iPad lytter på channel: \(channelName)")
        
        listeningTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.checkForIncomingCall()
        }
    }
    
    private func checkForIncomingCall() {
        if showOutgoingCall {
            return
        }
        
        if agoraManager.remoteUserID > 0 && !showIncomingVideoCall {
            print("📞 PAUSESIDE: iPhone prøver å ringe!")
            
            listeningTimer?.invalidate()
            
            if let callerContact = contactManager.getContactsToCall().first(where: { !$0.instructionVideoURL.isEmpty }) {
                receiveCallFromiPhone(contact: callerContact)
            } else if let firstContact = contactManager.getContactsToCall().first {
                receiveCallFromiPhone(contact: firstContact)
            }
        }
    }
    
    private func receiveCallFromiPhone(contact: Contact) {
        print("📱 PAUSESIDE mottar anrop fra \(contact.name)")
        
        videoManager.completelyStopVideo()
        videoCallSimulator.simulateIncomingCall(from: contact)
        showIncomingVideoCall = true
    }
    
    private func handleRemoteUserJoined(uid: UInt) {
        if showOutgoingCall {
            print("👥 PAUSESIDE: Remote user \(uid) joined during outgoing call")
            return
        }
        
        if uid > 0 && !showIncomingVideoCall {
            print("👥 PAUSESIDE: Remote bruker detektert: \(uid)")
            
            if let contactWithVideo = contactManager.getContactsToCall().first(where: { !$0.instructionVideoURL.isEmpty }) {
                receiveCallFromiPhone(contact: contactWithVideo)
            } else {
                let defaultContact = Contact(
                    name: "Alf Bjarne",
                    phoneNumber: "+47 123 45 678",
                    relationship: "Familie",
                    instructionVideoURL: "alf_1754225825_instruction",
                    isApproved: true,
                    isMe: false
                )
                receiveCallFromiPhone(contact: defaultContact)
            }
        }
    }
    
    private func selectVideoContact() {
        let contactsWithVideo = contactManager.getContactsToCall().filter { !$0.instructionVideoURL.isEmpty }
        
        if let firstContact = contactsWithVideo.first {
            selectedVideoContact = firstContact
            print("📹 PAUSESIDE: Valgte video kontakt - \(firstContact.name)")
        } else {
            print("📹 PAUSESIDE: Ingen videoer tilgjengelig")
        }
    }
    
    private func startOutgoingCall(to contact: Contact) {
        print("\n==================================================")
        print("📱 iPad (Oddvar) RINGER TIL: \(contact.name)")
        print("📡 Channel: test_1308")
        print("==================================================\n")
        
        outgoingCallContact = contact
        showOutgoingCall = true
        isConnectingCall = true
        
        listeningTimer?.invalidate()
        
        agoraManager.startTestCallAsInitiator(channelName: "test_1308")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.isConnectingCall = false
            print("✅ Venter på at \(contact.name) skal svare...")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if self.showOutgoingCall && !self.agoraManager.isInCall {
                print("⏰ Ingen svar - avslutter anrop")
                self.endOutgoingCall()
            }
        }
    }
    
    private func endOutgoingCall() {
        print("📞 Avslutter utgående anrop fra iPad")
        
        showOutgoingCall = false
        outgoingCallContact = nil
        isConnectingCall = false
        
        agoraManager.endCall()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.setupAgoraListening()
        }
    }
    
    private func openPhoneInterface() {
        let callableContacts = contactManager.getContactsToCall()
        
        if callableContacts.isEmpty {
            print("❌ Ingen kontakter å ringe til")
            return
        }
        
        if callableContacts.count == 1 {
            startOutgoingCall(to: callableContacts.first!)
        } else {
            showingTestCall = true
        }
    }
}

// MARK: - Date Extensions
extension Date {
    var weekdayName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: self).capitalized
    }
    
    var monthName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "MMMM"
        return formatter.string(from: self).capitalized
    }
    
    var day: Int {
        Calendar.current.component(.day, from: self)
    }
    
    var yearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: self)
    }
    
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }
    
    var timeOfDay: String {
        switch timeOfDayPeriod {
        case .morning:
            return "formiddag"
        case .afternoon:
            return "ettermiddag"
        case .evening:
            return "kveld"
        case .night:
            return "natt"
        }
    }
    
    var timeOfDayPeriod: TimeOfDayPeriod {
        let hour = Calendar.current.component(.hour, from: self)
        
        switch hour {
        case 6..<12:
            return .morning
        case 12..<18:
            return .afternoon
        case 18..<22:
            return .evening
        default:
            return .night
        }
    }
}

enum TimeOfDayPeriod {
    case morning, afternoon, evening, night
}
