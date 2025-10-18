import Foundation
import SwiftUI

class ContactManager: ObservableObject {
    @Published var contacts: [Contact] = []
    @Published var isSyncing = false
    @Published var lastSyncTime: Date?
    @Published var syncError: String?
    
    private let userDefaults = UserDefaults.standard
    private let contactsKey = "SavedContacts"
    private let myContactKey = "MyContactID"
    private let cloudKitManager = CloudKitManager.shared
    
    // MARK: - Initialization
    init() {
        setupSampleVideoFiles()
        loadContacts()
        setupDefaultOddvarContact()
        updateContactVideoNames()
        
        // Start iCloud sync
        setupCloudKitSync()
    }
    
    // MARK: - CloudKit Setup
    private func setupCloudKitSync() {
        // Listen for CloudKit availability changes
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            self.syncWithCloud()
        }
        
        // Initial sync
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.syncWithCloud()
        }
        
        print("☁️ CloudKit sync aktivert")
    }
    
    // MARK: - Sync with iCloud
    func syncWithCloud() {
        guard cloudKitManager.iCloudAvailable else {
            print("⚠️ iCloud ikke tilgjengelig")
            return
        }
        
        Task {
            await MainActor.run {
                self.isSyncing = true
            }
            
            do {
                // Fetch contacts from cloud
                let cloudContacts = try await cloudKitManager.fetchContactsFromCloud()
                
                await MainActor.run {
                    self.mergeCloudContacts(cloudContacts)
                    self.lastSyncTime = Date()
                    self.isSyncing = false
                }
                
                // Upload any local-only contacts
                try await self.uploadLocalOnlyContacts(cloudContacts: cloudContacts)
                
                print("✅ Synkronisering fullført")
            } catch {
                await MainActor.run {
                    self.syncError = error.localizedDescription
                    self.isSyncing = false
                }
                print("❌ Sync feilet: \(error)")
            }
        }
    }
    
    // MARK: - Merge Cloud Contacts
    private func mergeCloudContacts(_ cloudContacts: [Contact]) {
        // Create a dictionary of existing contacts
        var existingDict = Dictionary(uniqueKeysWithValues: contacts.map { ($0.id.uuidString, $0) })
        
        // Add or update contacts from cloud
        for cloudContact in cloudContacts {
            existingDict[cloudContact.id.uuidString] = cloudContact
        }
        
        // Update contacts array
        contacts = Array(existingDict.values).sorted { $0.name < $1.name }
        saveContactsLocally()
        
        print("📱 Merged \(cloudContacts.count) cloud contacts")
    }
    
    // MARK: - Upload Local-Only Contacts
    private func uploadLocalOnlyContacts(cloudContacts: [Contact]) async throws {
        let cloudIDs = Set(cloudContacts.map { $0.id.uuidString })
        let localOnlyContacts = contacts.filter { !cloudIDs.contains($0.id.uuidString) }
        
        for contact in localOnlyContacts {
            try await cloudKitManager.saveContactToCloud(contact)
            print("📤 Uploaded: \(contact.name)")
        }
    }
    
    // MARK: - Force Sync
    func forceSyncWithCloud() {
        print("🔄 Tvungen synkronisering startet...")
        syncWithCloud()
    }
    
    // MARK: - Add Contact (with Cloud Sync)
    func addContact(_ contact: Contact) {
        contacts.append(contact)
        saveContactsLocally()
        print("✅ Kontakt lagt til lokalt: \(contact.name)")
        
        // Upload to cloud
        Task {
            do {
                try await cloudKitManager.saveContactToCloud(contact)
                print("☁️ Kontakt lastet opp: \(contact.name)")
            } catch {
                print("⚠️ Kunne ikke laste opp kontakt: \(error)")
            }
        }
    }
    
    // MARK: - Remove Contact (with Cloud Sync)
    func removeContact(withId id: UUID) {
        contacts.removeAll { $0.id == id }
        saveContactsLocally()
        print("🗑️ Kontakt fjernet lokalt")
        
        // Delete from cloud
        Task {
            do {
                try await cloudKitManager.deleteContactFromCloud(id.uuidString)
                print("☁️ Kontakt slettet fra sky")
            } catch {
                print("⚠️ Kunne ikke slette fra sky: \(error)")
            }
        }
    }
    
    // MARK: - Update Contact with Video (with Cloud Sync)
    func updateContactWithVideo(_ contact: Contact, videoFileName: String) {
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            let updatedContact = Contact(
                id: contact.id,
                name: contact.name,
                phoneNumber: contact.phoneNumber,
                relationship: contact.relationship,
                instructionVideoURL: videoFileName,
                isApproved: contact.isApproved,
                isMe: contact.isMe
            )
            contacts[index] = updatedContact
            saveContactsLocally()
            print("✅ Kontakt oppdatert med video lokalt: \(videoFileName)")
            
            // Upload to cloud
            Task {
                do {
                    try await cloudKitManager.saveContactToCloud(updatedContact)
                    print("☁️ Video-oppdatering lastet opp")
                } catch {
                    print("⚠️ Kunne ikke laste opp video-oppdatering: \(error)")
                }
            }
        }
    }
    
    // MARK: - Set As Me (with Cloud Sync)
    func setAsMe(_ contact: Contact) {
        // Clear existing "me" status
        for i in 0..<contacts.count {
            if contacts[i].isMe {
                let updated = contacts[i].updated(isMe: false)
                contacts[i] = updated
                
                // Update in cloud
                Task {
                    try? await cloudKitManager.saveContactToCloud(updated)
                }
            }
        }
        
        // Set new "me"
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            let updated = contacts[index].updated(isMe: true)
            contacts[index] = updated
            
            // Update in cloud
            Task {
                try? await cloudKitManager.saveContactToCloud(updated)
                print("☁️ 'Meg' status oppdatert i sky")
            }
        }
        
        saveContactsLocally()
        print("👤 Satt \(contact.name) som 'meg'")
    }
    
    // MARK: - Save Contacts Locally
    private func saveContactsLocally() {
        if let data = try? JSONEncoder().encode(contacts) {
            userDefaults.set(data, forKey: contactsKey)
            print("💾 Kontakter lagret lokalt")
        }
    }
    
    // MARK: - Load Contacts
    func loadContacts() {
        loadSavedContacts()
        
        if contacts.isEmpty {
            loadSampleContacts()
        }
        
        print("👥 Lastet \(contacts.count) kontakter")
        printMyContact()
    }
    
    // MARK: - Existing methods (unchanged)
    
    private func loadSavedContacts() {
        if let data = userDefaults.data(forKey: contactsKey),
           let savedContacts = try? JSONDecoder().decode([Contact].self, from: data) {
            contacts = savedContacts
            print("💾 Lastet lagrede kontakter: \(savedContacts.count)")
        }
    }
    
    private func loadSampleContacts() {
        let deviceType = UIDevice.current.userInterfaceIdiom
        
        if deviceType == .pad {
            // iPad: Oddvar som eier
            contacts = [
                Contact(
                    name: "Oddvar",
                    phoneNumber: "+47 954 02 689",
                    relationship: "Meg selv",
                    instructionVideoURL: "sample_video",
                    isApproved: true,
                    isMe: true
                ),
                Contact(
                    name: "Alf Bjarne",
                    phoneNumber: "+47 123 45 678",
                    relationship: "Familie",
                    instructionVideoURL: "alf_1754225825_instruction",
                    isApproved: true,
                    isMe: false
                ),
                Contact(
                    name: "Tor Harald",
                    phoneNumber: "+47 987 65 432",
                    relationship: "Venn",
                    instructionVideoURL: "tor_harald_1754224593_instruction",
                    isApproved: true,
                    isMe: false
                ),
                Contact(
                    name: "Anna",
                    phoneNumber: "+47 555 12 345",
                    relationship: "Datter",
                    instructionVideoURL: "",
                    isApproved: true,
                    isMe: false
                ),
                Contact(
                    name: "Ole",
                    phoneNumber: "+47 444 67 890",
                    relationship: "Sønn",
                    instructionVideoURL: "",
                    isApproved: true,
                    isMe: false
                )
            ]
        } else {
            // iPhone: Ingen automatisk "me"
            contacts = [
                Contact(
                    name: "Oddvar",
                    phoneNumber: "+47 954 02 689",
                    relationship: "Familie",
                    instructionVideoURL: "alf_1754225825_instruction",
                    isApproved: true,
                    isMe: false
                ),
                Contact(
                    name: "Alf Bjarne",
                    phoneNumber: "+47 123 45 678",
                    relationship: "Familie",
                    instructionVideoURL: "alf_1754225825_instruction",
                    isApproved: true,
                    isMe: false
                ),
                Contact(
                    name: "Tor Harald",
                    phoneNumber: "+47 987 65 432",
                    relationship: "Venn",
                    instructionVideoURL: "tor_harald_1754224593_instruction",
                    isApproved: true,
                    isMe: false
                )
            ]
        }
        saveContactsLocally()
    }
    
    private func setupDefaultOddvarContact() {
        let deviceType = UIDevice.current.userInterfaceIdiom
        
        if deviceType == .pad && getMyContact() == nil {
            if let oddvarIndex = contacts.firstIndex(where: { $0.name == "Oddvar" }) {
                setAsMe(contacts[oddvarIndex])
                print("📱 AUTO: Satt Oddvar som iPad-eier")
            } else {
                let oddvarContact = Contact(
                    name: "Oddvar",
                    phoneNumber: "+47 954 02 689",
                    relationship: "Meg selv",
                    instructionVideoURL: "",
                    isApproved: true,
                    isMe: true
                )
                addContact(oddvarContact)
                print("📱 AUTO: Opprettet Oddvar som iPad-eier")
            }
        }
    }
    
    private func updateContactVideoNames() {
        print("🔧 Oppdaterer video-navn basert på tilgjengelige filer...")
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var availableVideos: [String] = []
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            availableVideos = files.filter { $0.pathExtension.lowercased() == "mp4" }
                                   .map { $0.deletingPathExtension().lastPathComponent }
            print("📹 Tilgjengelige videoer: \(availableVideos)")
        } catch {
            print("❌ Kunne ikke lese video-filer: \(error)")
        }
        
        for i in 0..<contacts.count {
            let contact = contacts[i]
            
            if !contact.instructionVideoURL.isEmpty {
                let currentVideoName = contact.instructionVideoURL
                var bestMatch: String? = nil
                
                if availableVideos.contains(currentVideoName) {
                    bestMatch = currentVideoName
                } else {
                    let searchName = contact.name.lowercased().replacingOccurrences(of: " ", with: "_")
                    bestMatch = availableVideos.first { video in
                        video.lowercased().contains(searchName) ||
                        video.lowercased().contains("alf") ||
                        video.lowercased().contains("tor")
                    }
                }
                
                if let match = bestMatch, match != currentVideoName {
                    print("🔧 Oppdaterer \(contact.name): '\(currentVideoName)' → '\(match)'")
                    
                    contacts[i] = Contact(
                        id: contact.id,
                        name: contact.name,
                        phoneNumber: contact.phoneNumber,
                        relationship: contact.relationship,
                        instructionVideoURL: match,
                        isApproved: contact.isApproved,
                        isMe: contact.isMe
                    )
                }
            }
        }
        
        saveContactsLocally()
    }
    
    private func setupSampleVideoFiles() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sampleVideoURL = documentsPath.appendingPathComponent("sample_video.mp4")
        
        if !FileManager.default.fileExists(atPath: sampleVideoURL.path) {
            let mp4Header = Data([
                0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70,
                0x69, 0x73, 0x6F, 0x6D, 0x00, 0x00, 0x02, 0x00,
                0x69, 0x73, 0x6F, 0x6D, 0x69, 0x73, 0x6F, 0x32,
                0x61, 0x76, 0x63, 0x31, 0x6D, 0x70, 0x34, 0x31
            ])
            
            try? mp4Header.write(to: sampleVideoURL)
            print("📹 Sample video fil opprettet: sample_video.mp4")
        }
    }
    
    // MARK: - Getters
    func getContact(by id: UUID) -> Contact? {
        return contacts.first { $0.id == id }
    }
    
    func getApprovedContacts() -> [Contact] {
        return contacts.filter { $0.isApproved }
    }
    
    func isContactApproved(_ contact: Contact) -> Bool {
        return contact.isApproved
    }
    
    func getMyContact() -> Contact? {
        return contacts.first { $0.isMe }
    }
    
    func getContactsToCall() -> [Contact] {
        return contacts.filter { !$0.isMe && $0.isApproved }
    }
    
    func canCallMe(fromPhone: String) -> Bool {
        guard let myContact = getMyContact() else { return false }
        
        let cleanFromPhone = cleanPhoneNumber(fromPhone)
        let cleanMyPhone = cleanPhoneNumber(myContact.phoneNumber)
        
        return cleanFromPhone == cleanMyPhone
    }
    
    func getCallerContact(fromPhone: String) -> Contact? {
        let cleanFromPhone = cleanPhoneNumber(fromPhone)
        
        return contacts.first { contact in
            let cleanContactPhone = cleanPhoneNumber(contact.phoneNumber)
            return cleanContactPhone == cleanFromPhone
        }
    }
    
    private func cleanPhoneNumber(_ phone: String) -> String {
        return phone.replacingOccurrences(of: " ", with: "")
                   .replacingOccurrences(of: "-", with: "")
                   .replacingOccurrences(of: "+47", with: "")
                   .replacingOccurrences(of: "(", with: "")
                   .replacingOccurrences(of: ")", with: "")
    }
    
    private func printMyContact() {
        if let myContact = getMyContact() {
            print("👤 JEG ER: \(myContact.name) (\(myContact.phoneNumber))")
        } else {
            print("❓ Ingen kontakt er satt som 'meg'")
        }
    }
    
    func getDeviceOwnerInfo() -> String {
        let deviceType = UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad"
        
        if let myContact = getMyContact() {
            return "\(deviceType): \(myContact.name)"
        } else {
            return "\(deviceType): Ukjent eier"
        }
    }
    
    func cleanupAndFixVideos() {
        // Existing cleanup code...
    }
}
