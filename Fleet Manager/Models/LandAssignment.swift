import Foundation
import SwiftData
import FirebaseAuth

@Model
final class LandAssignment {
    // Remove unique constraint for CloudKit compatibility
    var id: UUID?
    
    // Optional relationship with correct syntax
    var user: User?
    
    // All attributes must be optional or have defaults
    var dateHome: Date?
    var expectedJoiningDate: Date?
    var fleetType: String?
    var lastVessel: String?
    var email: String?
    var mobileNumber: String?
    var isPublic: Bool = true
    
    // User identifier for device matching
    var userIdentifier: String?
    
    init() {
        self.id = UUID()
        self.isPublic = true
    }
    
    init(user: User, dateHome: Date, expectedJoiningDate: Date, fleetType: String, lastVessel: String, email: String, mobileNumber: String, isPublic: Bool = true) {
        self.id = UUID()
        self.user = user
        self.dateHome = dateHome
        self.expectedJoiningDate = expectedJoiningDate
        self.fleetType = fleetType
        self.lastVessel = lastVessel
        self.email = email
        self.mobileNumber = mobileNumber
        self.isPublic = isPublic
        self.userIdentifier = user.userIdentifier ?? Auth.auth().currentUser?.uid
        
        // Add to user's assignments
        if var landAssignments = user.landAssignments {
            landAssignments.append(self)
            user.landAssignments = landAssignments
        } else {
            user.landAssignments = [self]
        }
        
        // Update user status to onLand
        user.currentStatus = .onLand
    }
    
    func matchesWithShipAssignment(_ shipAssignment: ShipAssignment) -> Bool {
        // Check if we have the necessary data for matching
        guard let expectedDate = expectedJoiningDate,
              let fleetType = self.fleetType,
              let landUser = self.user else {
            return false
        }
        
        // 1. Fleet compatibility - case insensitive comparison
        // Check if user's fleet working matches the ship assignment
        let shipFleet = shipAssignment.user?.fleetWorking?.lowercased() ?? ""
        if !fleetType.lowercased().contains(shipFleet) && !shipFleet.contains(fleetType.lowercased()) {
            return false
        }
        
        // 2. Rank compatibility - case insensitive comparison
        let landRank = landUser.presentRank?.lowercased() ?? ""
        let shipRank = shipAssignment.rank?.lowercased() ?? ""
        if landRank.isEmpty || shipRank.isEmpty || landRank != shipRank {
            return false
        }
        
        // 3. Company compatibility (if specified)
        if let shipCompany = shipAssignment.company, !shipCompany.isEmpty {
            // If company is specified on the ship, it should match
            let userCompany = landUser.company?.lowercased() ?? ""
            if !userCompany.isEmpty && userCompany != shipCompany.lowercased() {
                return false
            }
        }
        
        // 4. Date compatibility - Check if release date is within a reasonable window of expected join date
        // Get ship release date
        let shipReleaseDate = shipAssignment.expectedReleaseDate
        
        // Calculate a window of +/- 30 days around the expected joining date
        let calendar = Calendar.current
        let thirtyDaysBefore = calendar.date(byAdding: .day, value: -30, to: expectedDate) ?? expectedDate
        let thirtyDaysAfter = calendar.date(byAdding: .day, value: 30, to: expectedDate) ?? expectedDate
        
        // Check if ship release date falls within this window
        return shipReleaseDate >= thirtyDaysBefore && shipReleaseDate <= thirtyDaysAfter
    }
} 