// Add this to your ContentView.swift
// Replace the beginning of your ContentView body with this:

struct ContentView: View {
    @StateObject private var contactManager = ContactManager()
    @StateObject private var videoManager = VideoManager()
    @StateObject private var videoCallSimulator = VideoCallSimulator()
    // ... other existing properties ...
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // ADD THIS: Sync Status at the top
                SyncStatusView(contactManager: contactManager)
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                // Your existing content
                HStack(spacing: 20) {
                    // VENSTRE SIDE - Kontaktliste
                    contactListView
                        .frame(width: 320)
                    
                    // HØYRE SIDE
                    if showOutgoingCall {
                        outgoingCallView
                            .frame(maxWidth: .infinity)
                    } else {
                        videoDisplayView
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                
                // Rest of your existing code...
            }
            .navigationTitle("📞 DemensApp - Video Kontakter")
            // ... rest of your navigation setup
        }
    }
}
