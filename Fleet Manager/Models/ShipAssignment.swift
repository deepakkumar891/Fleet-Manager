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
    var signOffDate: Date?
    var fleetType: String?
    
    
    // User identifier for device matching
    var userIdentifier: String?
    
    init() {
        self.id = UUID()
        self.contractLength = 6
        self.isPublic = true
    }
    
    init(user: User, dateOfOnboard: Date, rank: String, shipName: String, company: String, contractLength: Int, portOfJoining: String, email: String, mobileNumber: String, isPublic: Bool = true, fleetWorking: String) {
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
        self.fleetType = user.fleetWorking
        
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
    
    var expectedReleaseDate: Date? {
        guard let onboardDate = dateOfOnboard else { return Date() }
        return Calendar.current.date(byAdding: .month, value: contractLength, to: onboardDate) ?? onboardDate
    }
    
    func matchesWithLandAssignment(_ landAssignment: LandAssignment) -> Bool {
        print("\n🔍 SHIP→LAND MATCH CHECK: Ship: \(shipName ?? "unknown"), Rank: \(rank ?? "unknown")")
        
        // Check if we have the necessary data for matching
        guard let expectedSignOffDate = expectedReleaseDate else {
            print("❌ Missing expected sign-off date")
            return false
        }
        
        guard let fleetType = self.fleetType else {
            print("❌ Missing fleet type")
            return false
        }
        
        guard let shipRank = self.rank?.lowercased() else {
            print("❌ Missing ship rank")
            return false
        }
        
        guard let expectedJoiningDate = landAssignment.expectedJoiningDate else {
            print("❌ Missing expected joining date")
            return false
        }
        
        guard let landUser = landAssignment.user else {
            print("❌ Missing land user")
            return false
        }
        
        guard let landRank = landUser.presentRank?.lowercased() else {
            print("❌ Missing land user rank")
            return false
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        
        print("🚢 Ship Details - Fleet: '\(fleetType)', Rank: '\(shipRank)', Sign-off: \(dateFormatter.string(from: expectedSignOffDate))")
        print("🏠 Land Details - Fleet: '\(landAssignment.fleetType ?? "unknown")', Rank: '\(landRank)', Joining: \(dateFormatter.string(from: expectedJoiningDate))")
        
        // 1. Fleet compatibility - case insensitive comparison
        let landFleet = landAssignment.fleetType?.lowercased() ?? ""
        if !fleetType.lowercased().contains(landFleet) && !landFleet.contains(fleetType.lowercased()) {
            print("❌ Fleet mismatch: Ship '\(fleetType.lowercased())' vs Land '\(landFleet)'")
            return false
        }
        
        print("✅ Fleet match: Ship '\(fleetType.lowercased())' compatible with Land '\(landFleet)'")
        
        // 2. Rank compatibility - case insensitive comparison
        if landRank.isEmpty || shipRank.isEmpty || landRank != shipRank {
            print("❌ Rank mismatch: Ship '\(shipRank)' vs Land '\(landRank)'")
            return false
        }
        
        print("✅ Rank match: Ship '\(shipRank)' matches Land '\(landRank)'")
        
        // 3. Company compatibility (if specified)
        if let shipCompany = company, !shipCompany.isEmpty {
            // Get the land user's company
            let landCompany = landAssignment.company?.lowercased() ?? landUser.company?.lowercased() ?? ""
            
            print("🏢 Company check - Ship: '\(shipCompany.lowercased())', Land: '\(landCompany)'")
            
            // If both companies are specified, they should match
            if !landCompany.isEmpty && !shipCompany.lowercased().isEmpty &&
               landCompany != shipCompany.lowercased() {
                print("❌ Company mismatch: Ship '\(shipCompany.lowercased())' vs Land '\(landCompany)'")
                return false
            }
            
            print("✅ Company match: Ship '\(shipCompany.lowercased())' compatible with Land '\(landCompany)'")
        }
        
        // 4. Date compatibility - Check if expected sign-off date is within a reasonable window of the land assignment's expected joining date
        // Calculate a window of +/- 30 days around the expected sign-off date
        let calendar = Calendar.current
        let thirtyDaysBefore = calendar.date(byAdding: .day, value: -15, to: expectedSignOffDate) ?? expectedSignOffDate
        let thirtyDaysAfter = calendar.date(byAdding: .day, value: 15, to: expectedSignOffDate) ?? expectedSignOffDate
        
        print("📅 Date window: \(dateFormatter.string(from: thirtyDaysBefore)) to \(dateFormatter.string(from: thirtyDaysAfter))")
        print("📅 Expected join date to check: \(dateFormatter.string(from: expectedJoiningDate))")
        
        // Check if expected joining date falls within this window around the sign-off date
        let dateMatch = expectedJoiningDate >= thirtyDaysBefore && expectedJoiningDate <= thirtyDaysAfter
        
        if dateMatch {
            print("✅ Date match: Land joining date \(dateFormatter.string(from: expectedJoiningDate)) is within window")
        } else {
            print("❌ Date mismatch: Land joining date \(dateFormatter.string(from: expectedJoiningDate)) is outside window")
        }
        
        print("🎯 Final match result: \(dateMatch ? "MATCH ✅" : "NO MATCH ❌")")
        return dateMatch
    }
    
}
