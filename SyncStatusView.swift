import SwiftUI

struct SyncStatusView: View {
    @ObservedObject var contactManager: ContactManager
    @ObservedObject var cloudKitManager = CloudKitManager.shared
    @State private var showDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main Status Row
            HStack {
                statusIcon
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.headline)
                    
                    if let lastSync = cloudKitManager.lastSyncDate {
                        Text("Sist synkronisert: \(lastSync, style: .relative)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if cloudKitManager.iCloudAvailable {
                    Button(action: {
                        contactManager.forceSyncWithCloud()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                            .rotationEffect(.degrees(contactManager.isSyncing ? 360 : 0))
                            .animation(
                                contactManager.isSyncing ?
                                Animation.linear(duration: 1).repeatForever(autoreverses: false) :
                                .default,
                                value: contactManager.isSyncing
                            )
                    }
                    .disabled(contactManager.isSyncing)
                }
                
                Button(action: { showDetails.toggle() }) {
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            
            // Detailed Information
            if showDetails {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    // iCloud Status
                    HStack {
                        Image(systemName: "icloud")
                            .foregroundColor(cloudKitManager.iCloudAvailable ? .green : .red)
                        Text(cloudKitManager.iCloudAvailable ? "iCloud tilgjengelig" : "iCloud ikke tilgjengelig")
                            .font(.subheadline)
                    }
                    
                    // Contact Count
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.blue)
                        Text("\(contactManager.contacts.count) kontakter")
                            .font(.subheadline)
                    }
                    
                    // Sync Status
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.orange)
                        Text(cloudKitManager.syncStatus.description)
                            .font(.subheadline)
                    }
                    
                    // Error Message
                    if let error = cloudKitManager.syncError {
                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .lineLimit(2)
                        }
                    }
                    
                    // Device Info
                    HStack {
                        Image(systemName: UIDevice.current.userInterfaceIdiom == .phone ? "iphone" : "ipad")
                            .foregroundColor(.gray)
                        Text(contactManager.getDeviceOwnerInfo())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundcolor)
                .shadow(color: Color.black.opacity(0.1), radius: 2)
        )
    }
    
    private var statusIcon: some View {
        Group {
            if contactManager.isSyncing {
                ProgressView()
                    .scaleEffect(0.8)
            } else if cloudKitManager.iCloudAvailable {
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            } else {
                Image(systemName: "xmark.icloud.fill")
                    .foregroundColor(.red)
                    .font(.title2)
            }
        }
        .frame(width: 30)
    }
    
    private var statusTitle: String {
        if contactManager.isSyncing {
            return "Synkroniserer..."
        } else if cloudKitManager.iCloudAvailable {
            return "Synkronisert med iCloud"
        } else {
            return "Kun lokal lagring"
        }
    }
    
    private var backgroundcolor: Color {
        if !cloudKitManager.iCloudAvailable {
            return Color.red.opacity(0.1)
        } else if contactManager.isSyncing {
            return Color.blue.opacity(0.1)
        } else {
            return Color.green.opacity(0.1)
        }
    }
}

// MARK: - Compact Sync Badge
struct SyncBadgeView: View {
    @ObservedObject var contactManager: ContactManager
    @ObservedObject var cloudKitManager = CloudKitManager.shared
    
    var body: some View {
        HStack(spacing: 4) {
            if contactManager.isSyncing {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Image(systemName: cloudKitManager.iCloudAvailable ? "checkmark.icloud" : "xmark.icloud")
                    .font(.caption)
                    .foregroundColor(cloudKitManager.iCloudAvailable ? .green : .red)
            }
            
            if contactManager.isSyncing {
                Text("Synkroniserer...")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.gray.opacity(0.2))
        )
    }
}
