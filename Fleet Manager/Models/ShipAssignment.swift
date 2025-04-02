import Foundation
import SwiftData
import FirebaseAuth

@Model
final class ShipAssignment {
    // Remove unique constraint for CloudKit compatibility
    var id: UUID?
    
    // Optional relationship with correct syntax
    var user: User?
    
    // All attributes must be optional or have defaults
    var dateOfOnboard: Date?
    var rank: String?
    var shipName: String?
    var company: String?  // New field for company
    var portOfJoining: String?
    var contractLength: Int = 6 // Default value
    var email: String?
    var mobileNumber: String?
    var isPublic: Bool = true
    
    // User identifier for device matching
    var userIdentifier: String?
    
    init() {
        self.id = UUID()
        self.contractLength = 6
        self.isPublic = true
    }
    
    init(user: User, dateOfOnboard: Date, rank: String, shipName: String, company: String, contractLength: Int, portOfJoining: String, email: String, mobileNumber: String, isPublic: Bool = true) {
        self.id = UUID()
        self.user = user
        self.dateOfOnboard = dateOfOnboard
        self.rank = rank
        self.shipName = shipName
        self.company = company
        self.portOfJoining = portOfJoining
        self.contractLength = contractLength
        self.email = email
        self.mobileNumber = mobileNumber
        self.isPublic = isPublic
        self.userIdentifier = user.userIdentifier ?? Auth.auth().currentUser?.uid
        
        // Add to user's assignments
        if var shipAssignments = user.shipAssignments {
            shipAssignments.append(self)
            user.shipAssignments = shipAssignments
        } else {
            user.shipAssignments = [self]
        }
        
        // Update user status to onShip
        user.currentStatus = .onShip
    }
    
    var expectedReleaseDate: Date {
        guard let onboardDate = dateOfOnboard else { return Date() }
        return Calendar.current.date(byAdding: .month, value: contractLength, to: onboardDate) ?? onboardDate
    }
} 