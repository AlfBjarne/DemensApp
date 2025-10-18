import SwiftUI

struct PhoneInterfaceView: View {
    let contactManager: ContactManager
    let onCall: (Contact) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("📞 Telefon")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)
                
                Text("Velg hvem du vil ringe til:")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                ScrollView {
                    LazyVStack(spacing: 15) {
                        ForEach(contactManager.getContactsToCall()) { contact in
                            ContactCallButton(contact: contact) {
                                print("📞 Ring til \(contact.name)")
                                onCall(contact)
                                dismiss()
                            }
                        }
                    }
                    .padding()
                }
                
                if contactManager.getContactsToCall().isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "phone.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("Ingen kontakter å ringe til")
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                    .padding()
                }
                
                Spacer()
            }
            .navigationTitle("Telefon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Ferdig") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ContactCallButton: View {
    let contact: Contact
    let onCall: () -> Void
    
    var body: some View {
        Button(action: onCall) {
            HStack(spacing: 15) {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Text(String(contact.name.first ?? "?"))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(contact.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(contact.relationship)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(contact.phoneNumber)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "phone.fill")
                    .font(.title2)
                    .foregroundColor(.green)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
