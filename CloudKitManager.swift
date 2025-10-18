import Foundation
import CloudKit
import SwiftUI

// MARK: - CloudKit Manager for Contact Synchronization
class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()
    
    // MARK: - Published Properties
    @Published var iCloudAvailable = false
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    
    // MARK: - CloudKit Properties
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let recordType = "Contact"
    private let zoneID = CKRecordZone.ID(zoneName: "ContactsZone", ownerName: CKCurrentUserDefaultName)
    
    // MARK: - Sync Status
    enum SyncStatus {
        case idle
        case syncing
        case success
        case error(String)
        
        var description: String {
            switch self {
            case .idle: return "Klar"
            case .syncing: return "Synkroniserer..."
            case .success: return "Synkronisert"
            case .error(let message): return "Feil: \(message)"
            }
        }
    }
    
    // MARK: - Initialization
    private init() {
        container = CKContainer.default()
        privateDatabase = container.privateCloudDatabase
        
        setupCloudKit()
        checkiCloudAvailability()
    }
    
    // MARK: - Setup CloudKit
    private func setupCloudKit() {
        // Create custom zone for better sync control
        let zone = CKRecordZone(zoneID: zoneID)
        
        privateDatabase.save(zone) { _, error in
            if let error = error {
                print("⚠️ CloudKit zone setup error: \(error.localizedDescription)")
            } else {
                print("✅ CloudKit zone created/verified")
            }
        }
        
        // Setup subscription for changes
        setupSubscription()
    }
    
    // MARK: - Check iCloud Availability
    private func checkiCloudAvailability() {
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    self?.iCloudAvailable = true
                    print("☁️ iCloud tilgjengelig")
                case .noAccount:
                    self?.iCloudAvailable = false
                    self?.syncError = "Ingen iCloud-konto pålogget"
                    print("❌ Ingen iCloud-konto")
                case .restricted, .couldNotDetermine:
                    self?.iCloudAvailable = false
                    self?.syncError = "iCloud ikke tilgjengelig"
                    print("❌ iCloud begrenset eller ukjent")
                default:
                    self?.iCloudAvailable = false
                    self?.syncError = "iCloud status ukjent"
                }
            }
        }
    }
    
    // MARK: - Setup Push Notifications
    private func setupSubscription() {
        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: "contact-changes",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        privateDatabase.save(subscription) { _, error in
            if let error = error {
                print("⚠️ Subscription error: \(error.localizedDescription)")
            } else {
                print("✅ CloudKit subscription active")
            }
        }
    }
    
    // MARK: - Save Contact to CloudKit
    func saveContactToCloud(_ contact: Contact) async throws {
        guard iCloudAvailable else {
            throw CloudKitError.iCloudNotAvailable
        }
        
        await MainActor.run {
            self.syncStatus = .syncing
        }
        
        let record = createRecord(from: contact)
        
        do {
            _ = try await privateDatabase.save(record)
            print("☁️ Kontakt lagret til iCloud: \(contact.name)")
            
            await MainActor.run {
                self.syncStatus = .success
                self.lastSyncDate = Date()
            }
        } catch {
            await MainActor.run {
                self.syncStatus = .error(error.localizedDescription)
                self.syncError = error.localizedDescription
            }
            throw error
        }
    }
    
    // MARK: - Fetch All Contacts from CloudKit
    func fetchContactsFromCloud() async throws -> [Contact] {
        guard iCloudAvailable else {
            throw CloudKitError.iCloudNotAvailable
        }
        
        await MainActor.run {
            self.syncStatus = .syncing
        }
        
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]
        
        do {
            let results = try await privateDatabase.records(matching: query, inZoneWith: zoneID)
            let contacts = results.matchResults.compactMap { _, result in
                try? result.get()
            }.compactMap { record in
                self.createContact(from: record)
            }
            
            print("☁️ Hentet \(contacts.count) kontakter fra iCloud")
            
            await MainActor.run {
                self.syncStatus = .success
                self.lastSyncDate = Date()
            }
            
            return contacts
        } catch {
            await MainActor.run {
                self.syncStatus = .error(error.localizedDescription)
                self.syncError = error.localizedDescription
            }
            throw error
        }
    }
    
    // MARK: - Delete Contact from CloudKit
    func deleteContactFromCloud(_ contactID: String) async throws {
        guard iCloudAvailable else {
            throw CloudKitError.iCloudNotAvailable
        }
        
        let recordID = CKRecord.ID(recordName: contactID, zoneID: zoneID)
        
        do {
            _ = try await privateDatabase.deleteRecord(withID: recordID)
            print("☁️ Kontakt slettet fra iCloud: \(contactID)")
        } catch {
            print("⚠️ Kunne ikke slette kontakt: \(error)")
            throw error
        }
    }
    
    // MARK: - Sync All Contacts
    func syncAllContacts(_ localContacts: [Contact]) async throws {
        guard iCloudAvailable else {
            throw CloudKitError.iCloudNotAvailable
        }
        
        await MainActor.run {
            self.syncStatus = .syncing
        }
        
        // Fetch cloud contacts
        let cloudContacts = try await fetchContactsFromCloud()
        
        // Create lookup dictionaries
        let cloudDict = Dictionary(uniqueKeysWithValues: cloudContacts.map { ($0.id.uuidString, $0) })
        let localDict = Dictionary(uniqueKeysWithValues: localContacts.map { ($0.id.uuidString, $0) })
        
        // Find contacts to upload (in local but not in cloud)
        let toUpload = localContacts.filter { cloudDict[$0.id.uuidString] == nil }
        
        // Find contacts to download (in cloud but not in local)
        let toDownload = cloudContacts.filter { localDict[$0.id.uuidString] == nil }
        
        // Upload new local contacts
        for contact in toUpload {
            try await saveContactToCloud(contact)
        }
        
        print("☁️ Synkronisering fullført:")
        print("   📤 Lastet opp: \(toUpload.count)")
        print("   📥 Lastet ned: \(toDownload.count)")
        
        await MainActor.run {
            self.syncStatus = .success
            self.lastSyncDate = Date()
        }
    }
    
    // MARK: - Create CKRecord from Contact
    private func createRecord(from contact: Contact) -> CKRecord {
        let recordID = CKRecord.ID(recordName: contact.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        
        record["id"] = contact.id.uuidString
        record["name"] = contact.name
        record["phoneNumber"] = contact.phoneNumber
        record["relationship"] = contact.relationship
        record["instructionVideoURL"] = contact.instructionVideoURL
        record["isApproved"] = contact.isApproved ? 1 : 0
        record["isMe"] = contact.isMe ? 1 : 0
        record["modificationDate"] = Date()
        
        return record
    }
    
    // MARK: - Create Contact from CKRecord
    private func createContact(from record: CKRecord) -> Contact? {
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = record["name"] as? String,
              let phoneNumber = record["phoneNumber"] as? String,
              let relationship = record["relationship"] as? String else {
            return nil
        }
        
        let instructionVideoURL = record["instructionVideoURL"] as? String ?? ""
        let isApproved = (record["isApproved"] as? Int ?? 1) == 1
        let isMe = (record["isMe"] as? Int ?? 0) == 1
        
        return Contact(
            id: id,
            name: name,
            phoneNumber: phoneNumber,
            relationship: relationship,
            instructionVideoURL: instructionVideoURL,
            isApproved: isApproved,
            isMe: isMe
        )
    }
    
    // MARK: - Check for Updates
    func checkForUpdates() {
        guard iCloudAvailable else { return }
        
        Task {
            do {
                _ = try await fetchContactsFromCloud()
            } catch {
                print("⚠️ Update check failed: \(error)")
            }
        }
    }
}

// MARK: - CloudKit Errors
enum CloudKitError: LocalizedError {
    case iCloudNotAvailable
    case syncFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .iCloudNotAvailable:
            return "iCloud er ikke tilgjengelig. Sjekk at du er pålogget iCloud."
        case .syncFailed(let message):
            return "Synkronisering feilet: \(message)"
        }
    }
}
