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
    var company: String?
    
    // User identifier for device matching
    var userIdentifier: String?
    
    init() {
        self.id = UUID()
        self.isPublic = true
    }
    
    init(user: User, dateHome: Date, expectedJoiningDate: Date, fleetType: String, lastVessel: String, email: String, mobileNumber: String, isPublic: Bool = true, company: String) {
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
        self.company = company
        
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
        print("\n🔍 LAND→SHIP MATCH CHECK: User: \(user?.name ?? "unknown") \(user?.surname ?? "unknown")")
        
        // Check if we have the necessary data for matching
        guard let expectedDate = expectedJoiningDate,
              let fleetType = self.fleetType,
              let landUser = self.user else {
            print("❌ Missing required data for matching")
            return false
        }
        
        // 1. Fleet compatibility - case insensitive comparison
        // Check if user's fleet working matches the ship assignment
        let shipFleet = shipAssignment.user?.fleetWorking?.lowercased() ?? ""
        if !fleetType.lowercased().contains(shipFleet) && !shipFleet.contains(fleetType.lowercased()) {
            print("❌ Fleet mismatch: Land '\(fleetType)' vs Ship '\(shipFleet)'")
            return false
        }
        
        print("✅ Fleet match")
        
        // 2. Rank compatibility - case insensitive comparison
        let landRank = landUser.presentRank?.lowercased() ?? ""
        let shipRank = shipAssignment.rank?.lowercased() ?? ""
        if landRank.isEmpty || shipRank.isEmpty || landRank != shipRank {
            print("❌ Rank mismatch: Land '\(landRank)' vs Ship '\(shipRank)'")
            return false
        }
        
        print("✅ Rank match")
        
        // 3. Company compatibility (if specified)
        if let shipCompany = shipAssignment.company, !shipCompany.isEmpty {
            // Get the land user's company (either from this assignment or from the user)
            let landCompany = self.company?.lowercased() ?? landUser.company?.lowercased() ?? ""
            
            // If both companies are specified, they should match
            if !landCompany.isEmpty && !shipCompany.lowercased().isEmpty &&
               landCompany != shipCompany.lowercased() {
                print("❌ Company mismatch: Land '\(landCompany)' vs Ship '\(shipCompany)'")
                return false
            }
        }
        
        print("✅ Company match")
        
        // 4. Date compatibility - Check if release date is within a reasonable window of expected join date
        // Get ship release date
        let shipReleaseDate = shipAssignment.expectedReleaseDate ?? Date.now
        
        // Calculate a window of +/- 30 days around the expected joining date
        let calendar = Calendar.current
        let thirtyDaysBefore = calendar.date(byAdding: .day, value: -15, to: expectedDate) ?? expectedDate
        let thirtyDaysAfter = calendar.date(byAdding: .day, value: 15, to: expectedDate) ?? expectedDate
        
        // Check if ship release date falls within this window
        let isMatch = shipReleaseDate >= thirtyDaysBefore && shipReleaseDate <= thirtyDaysAfter
        
        if isMatch {
            print("✅ Date match - MATCH FOUND!")
        } else {
            print("❌ Date mismatch")
        }
        
        return isMatch
    }
    
    func printAuthStatus() {
        if let user = Auth.auth().currentUser {
            print("✅ Current user authenticated: \(user.uid)")
            user.getIDTokenResult { result, error in
                if let error = error {
                    print("❌ Error getting token: \(error.localizedDescription)")
                    return
                }
                
                if let result = result {
                    print("📝 Token expires: \(result.expirationDate)")
                    print("📝 Authentication time: \(result.authDate)")
                    print("📝 Is user admin: \(result.claims["admin"] as? Bool ?? false)")
                }
            }
        } else {
            print("❌ No user authenticated!")
        }
    }
}
