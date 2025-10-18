import Foundation
import SwiftUI

struct Contact: Identifiable, Codable {
    let id: UUID
    let name: String
    let phoneNumber: String
    let relationship: String
    let instructionVideoURL: String
    let isApproved: Bool
    let isMe: Bool  // NY: Indikerer om dette er meg
    
    init(
        id: UUID = UUID(),
        name: String,
        phoneNumber: String,
        relationship: String,
        instructionVideoURL: String = "",
        isApproved: Bool = true,
        isMe: Bool = false  // NY: Default er ikke meg
    ) {
        self.id = id
        self.name = name
        self.phoneNumber = phoneNumber
        self.relationship = relationship
        self.instructionVideoURL = instructionVideoURL
        self.isApproved = isApproved
        self.isMe = isMe
    }
    
    // Helper for å opprette en oppdatert versjon
    func updated(isMe: Bool) -> Contact {
        return Contact(
            id: self.id,
            name: self.name,
            phoneNumber: self.phoneNumber,
            relationship: self.relationship,
            instructionVideoURL: self.instructionVideoURL,
            isApproved: self.isApproved,
            isMe: isMe
        )
    }
}
