import Foundation
import SwiftData
import FirebaseAuth

@Model
final class User {
    // Remove unique constraint for CloudKit compatibility
    var id: UUID?
    
    // Keep relationships optional for model compatibility
    var shipAssignments: [ShipAssignment]?
    var landAssignments: [LandAssignment]?
    
    // All attributes must be optional or have default values
    var name: String?
    var surname: String?
    var email: String?
    var password: String?
    var mobileNumber: String?
    var fleetWorking: String?
    var presentRank: String?
    
    // Privacy settings
    var isProfileVisible: Bool = true
    var showEmailToOthers: Bool = true
    var showPhoneToOthers: Bool = true
    
    // Using fully qualified default value
    var currentStatus: UserStatus = UserStatus.onLand
    
    // User identifier for Firebase Auth
    var userIdentifier: String?
    
    // New field for company
    var company: String?
    
    // Empty initializer required for SwiftData
    init() {
        self.id = UUID()
        self.shipAssignments = []
        self.landAssignments = []
    }
    
    // Full initializer
    init(name: String, surname: String, email: String, password: String, mobileNumber: String, fleetWorking: String, presentRank: String, company: String? = nil) {
        self.id = UUID()
        self.name = name
        self.surname = surname
        self.email = email
        self.password = password
        self.mobileNumber = mobileNumber
        self.fleetWorking = fleetWorking
        self.presentRank = presentRank
        self.currentStatus = UserStatus.onLand
        self.shipAssignments = []
        self.landAssignments = []
        self.userIdentifier = Auth.auth().currentUser?.uid ?? UserDefaults.standard.string(forKey: "userIdentifier")
        self.isProfileVisible = true
        self.showEmailToOthers = true
        self.showPhoneToOthers = true
        self.company = company
    }
}

enum UserStatus: String, Codable {
    case onShip
    case onLand
} 