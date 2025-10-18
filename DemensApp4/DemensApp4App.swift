import SwiftUI

@main
struct DemensApp4App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var contactManager = ContactManager()  // Opprett én gang her
    
    var body: some Scene {
        WindowGroup {
            // SMART DEVICE DETECTION
            if UIDevice.current.userInterfaceIdiom == .pad {
                // iPad: Vis pauseside med stor dato/tid
                iPadHomeView()
                    .environmentObject(contactManager)  // Pass via environment
            } else {
                // iPhone: Vis vanlig kontakt-interface
                ContentView()
                    .environmentObject(contactManager)  // Pass via environment
            }
        }
    }
}
