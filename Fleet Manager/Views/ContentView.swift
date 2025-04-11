import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAuth

struct ContentView: View {
    @AppStorage("userId") private var userId = ""
    @State private var isCheckingAuth = false
    @State private var showAuthError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]
    @Query private var shipAssignments: [ShipAssignment]
    @Query private var landAssignments: [LandAssignment]
    
    var body: some View {
        ZStack {
            if isCheckingAuth {
                // Initial loading state
                ProgressView("Verifying authentication...")
                    .padding()
            } else {
                // Show appropriate view based on authentication status
                if userId.isEmpty {
                    LoginView()
                } else {
                    MainTabView()
                }
            }
        }
        .onAppear {
            // Check if user is already signed in with Firebase
            isCheckingAuth = true
            
            if FirebaseService.shared.isUserSignedIn() {
                // User is already signed in
                if let currentUserId = FirebaseService.shared.getCurrentUserId() {
                    userId = currentUserId
                    // Fetch user profile from Firebase (not local storage)
                    fetchUserProfileFromFirebase(userId: currentUserId)
                } else {
                    // No valid Firebase user ID
                    isCheckingAuth = false
                }
            } else {
                // Not signed in
                isCheckingAuth = false
            }
        }
        .alert(isPresented: $showAuthError) {
            Alert(
                title: Text("Authentication Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK")) {
                    // Clear userId if there's an error
                    userId = ""
                    isCheckingAuth = false
                }
            )
        }
    }
    
    private func fetchUserProfileFromFirebase(userId: String) {
        FirebaseService.shared.fetchUserProfile{ result in
            DispatchQueue.main.async {
                switch result {
                case .success(let userData):
                    // Create or update local user from Firebase data
                    createOrUpdateLocalUser(userId: userId, userData: userData)
                    
                    // Now check for existing assignments to prevent duplicates
                    checkExistingUserAssignments()
                    
                case .failure(let error):
                    print("Failed to fetch user profile: \(error.localizedDescription)")
                    errorMessage = "Could not retrieve your profile. Please sign in again."
                    showAuthError = true
                }
            }
        }
    }
    
    private func checkExistingUserAssignments() {
        guard let userId = FirebaseService.shared.getCurrentUserId() else {
            print("⚠️ No user ID available")
            return
        }
        
        // First cleanup any duplicate assignments
        cleanupDuplicateAssignments(userId: userId) {
            // Then fetch the latest assignments
            DispatchQueue.main.async {
                self.isLoading = true
            }
            
            // First, check ship assignments
            FirebaseService.shared.fetchUserAssignments(userId: userId, collectionName: "shipAssignments") { result in
                switch result {
                case .success(let assignments):
                    DispatchQueue.main.async {
                        if let assignment = assignments.first {
                            self.updateLocalUserWithShipAssignment(assignment)
                        }
                        
                        // Next, check land assignments
                        FirebaseService.shared.fetchUserAssignments(userId: userId, collectionName: "landAssignments") { result in
                            DispatchQueue.main.async {
                                self.isLoading = false
                            }
                            
                            switch result {
                            case .success(let assignments):
                                DispatchQueue.main.async {
                                    if let assignment = assignments.first {
                                        self.updateLocalUserWithLandAssignment(assignment)
                                    }
                                    self.updateUserLastDeviceLogin(userId: userId)
                                }
                            case .failure(let error):
                                print("⚠️ Error fetching land assignments: \(error.localizedDescription)")
                                DispatchQueue.main.async {
                                    self.updateUserLastDeviceLogin(userId: userId)
                                }
                            }
                        }
                    }
                case .failure(let error):
                    print("⚠️ Error fetching ship assignments: \(error.localizedDescription)")
                    
                    // Even if ship assignments fail, still check land assignments
                    FirebaseService.shared.fetchUserAssignments(userId: userId, collectionName: "landAssignments") { result in
                        DispatchQueue.main.async {
                            self.isLoading = false
                        }
                        
                        switch result {
                        case .success(let assignments):
                            DispatchQueue.main.async {
                                if let assignment = assignments.first {
                                    self.updateLocalUserWithLandAssignment(assignment)
                                }
                                self.updateUserLastDeviceLogin(userId: userId)
                            }
                        case .failure(let error):
                            print("⚠️ Error fetching land assignments: \(error.localizedDescription)")
                            DispatchQueue.main.async {
                                self.updateUserLastDeviceLogin(userId: userId)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Cleanup function to remove duplicate assignments before syncing
    private func cleanupDuplicateAssignments(userId: String, completion: @escaping () -> Void) {
        let dispatchGroup = DispatchGroup()
        
        // First check and clean ship assignments
        dispatchGroup.enter()
        FirebaseService.shared.deleteAllUserAssignments(userId: userId, collectionName: "shipAssignments", keepOne: true) { result in
            defer { dispatchGroup.leave() }
            switch result {
            case .success(let count):
                if count > 0 {
                    print("🧹 Cleaned up \(count) duplicate ship assignments")
                }
            case .failure(let error):
                print("⚠️ Error during ship assignments cleanup: \(error.localizedDescription)")
            }
        }
        
        // Then check and clean land assignments
        dispatchGroup.enter()
        FirebaseService.shared.deleteAllUserAssignments(userId: userId, collectionName: "landAssignments", keepOne: true) { result in
            defer { dispatchGroup.leave() }
            switch result {
            case .success(let count):
                if count > 0 {
                    print("🧹 Cleaned up \(count) duplicate land assignments")
                }
            case .failure(let error):
                print("⚠️ Error during land assignments cleanup: \(error.localizedDescription)")
            }
        }
        
        // When both operations are complete, continue with the sync
        dispatchGroup.notify(queue: .main) {
            completion()
        }
    }
    
    private func fetchShipAssignments(userId: String) {
        FirebaseService.shared.fetchUserShipAssignments(userId: userId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let assignments):
                    for assignment in assignments {
                        // Add to local database if it doesn't already exist
                        if !self.shipAssignmentExists(with: assignment.id) {
                            self.modelContext.insert(assignment)
                        }
                    }
                    try? self.modelContext.save()
                    
                case .failure(let error):
                    print("Error fetching ship assignments: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func fetchLandAssignments(userId: String) {
        FirebaseService.shared.fetchUserLandAssignments(userId: userId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let assignments):
                    for assignment in assignments {
                        // Add to local database if it doesn't already exist
                        if !self.landAssignmentExists(with: assignment.id) {
                            self.modelContext.insert(assignment)
                        }
                    }
                    try? self.modelContext.save()
                    
                case .failure(let error):
                    print("Error fetching land assignments: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func shipAssignmentExists(with id: UUID?) -> Bool {
        guard let id = id else { return false }
        return shipAssignments.contains { $0.id == id }
    }
    
    private func landAssignmentExists(with id: UUID?) -> Bool {
        guard let id = id else { return false }
        return landAssignments.contains { $0.id == id }
    }
    
    private func createOrUpdateLocalUser(userId: String, userData: [String: Any]) {
        // Check if user already exists locally
        if let existingUser = users.first(where: { $0.userIdentifier == userId }) {
            // Update existing user
            updateUser(existingUser, with: userData)
        } else {
            // Create new user
            let newUser = User()
            newUser.userIdentifier = userId
            updateUser(newUser, with: userData)
            modelContext.insert(newUser)
        }
        
        // Save changes
        do {
            try modelContext.save()
        } catch {
            print("Error saving user data: \(error.localizedDescription)")
        }
    }
    
    private func updateUser(_ user: User, with userData: [String: Any]) {
        user.name = userData["name"] as? String
        user.surname = userData["surname"] as? String
        user.email = userData["email"] as? String
        user.mobileNumber = userData["mobileNumber"] as? String
        user.fleetWorking = userData["fleetWorking"] as? String
        user.presentRank = userData["presentRank"] as? String
        
        if let statusString = userData["currentStatus"] as? String,
           let status = UserStatus(rawValue: statusString) {
            user.currentStatus = status
        }
    }
    
    // Add missing function to update local user with ship assignment data
    private func updateLocalUserWithShipAssignment(_ assignment: [String: Any]) {
        guard let userId = FirebaseService.shared.getCurrentUserId(),
              let user = users.first(where: { $0.userIdentifier == userId }) else {
            print("⚠️ Could not find local user to update with ship assignment")
            return
        }
        
        // Create a new ShipAssignment
        let shipAssignment = ShipAssignment()
        shipAssignment.id = UUID()
        shipAssignment.userIdentifier = userId
        shipAssignment.shipName = assignment["shipName"] as? String
        shipAssignment.company = assignment["company"] as? String
        shipAssignment.fleetType = assignment["fleetType"] as? String
        shipAssignment.portOfJoining = assignment["portOfJoining"] as? String
        shipAssignment.rank = assignment["rank"] as? String
        shipAssignment.email = assignment["email"] as? String
        shipAssignment.mobileNumber = assignment["mobileNumber"] as? String
        shipAssignment.isPublic = assignment["isPublic"] as? Bool ?? true
        
        // Convert timestamps to dates
        if let timestamp = assignment["dateOfOnboard"] as? [String: Any],
           let seconds = timestamp["seconds"] as? Double {
            shipAssignment.dateOfOnboard = Date(timeIntervalSince1970: seconds)
        }
        
        if let contractLength = assignment["contractLength"] as? Int {
            shipAssignment.contractLength = contractLength
        }
        
        // Add to local database
        modelContext.insert(shipAssignment)
        
        // Connect to user
        if user.shipAssignments == nil {
            user.shipAssignments = [shipAssignment]
        } else {
            user.shipAssignments?.append(shipAssignment)
        }
        
        // Update user status
        user.currentStatus = UserStatus.onShip
        
        // Save changes
        try? modelContext.save()
        print("✅ Updated local user with ship assignment")
    }
    
    // Add missing function to update local user with land assignment data
    private func updateLocalUserWithLandAssignment(_ assignment: [String: Any]) {
        guard let userId = FirebaseService.shared.getCurrentUserId(),
              let user = users.first(where: { $0.userIdentifier == userId }) else {
            print("⚠️ Could not find local user to update with land assignment")
            return
        }
        
        // Create a new LandAssignment
        let landAssignment = LandAssignment()
        landAssignment.id = UUID()
        landAssignment.userIdentifier = userId
        landAssignment.lastVessel = assignment["lastVessel"] as? String
        landAssignment.company = assignment["company"] as? String
        landAssignment.fleetType = assignment["fleetType"] as? String
        landAssignment.email = assignment["email"] as? String
        landAssignment.mobileNumber = assignment["mobileNumber"] as? String
        landAssignment.isPublic = assignment["isPublic"] as? Bool ?? true
        
        // Convert timestamps to dates
        if let timestamp = assignment["dateHome"] as? [String: Any],
           let seconds = timestamp["seconds"] as? Double {
            landAssignment.dateHome = Date(timeIntervalSince1970: seconds)
        }
        
        if let timestamp = assignment["expectedJoiningDate"] as? [String: Any],
           let seconds = timestamp["seconds"] as? Double {
            landAssignment.expectedJoiningDate = Date(timeIntervalSince1970: seconds)
        }
        
        // Add to local database
        modelContext.insert(landAssignment)
        
        // Connect to user
        if user.landAssignments == nil {
            user.landAssignments = [landAssignment]
        } else {
            user.landAssignments?.append(landAssignment)
        }
        
        // Update user status
        user.currentStatus = UserStatus.onLand
        
        // Save changes
        try? modelContext.save()
        print("✅ Updated local user with land assignment")
    }
    
    // Add missing function to update user last device login
    private func updateUserLastDeviceLogin(userId: String) {
        // Complete the authentication process
        isCheckingAuth = false
        
        // Mark authentication complete
        print("✅ Successfully completed authentication and assignment sync")
        
        // Update the last device login timestamp in Firestore
        FirebaseService.shared.updateLastDeviceLogin(userId: userId) { error in
            if let error = error {
                print("⚠️ Failed to update last device login: \(error.localizedDescription)")
            } else {
                print("✅ Updated last device login timestamp")
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [User.self, ShipAssignment.self, LandAssignment.self], inMemory: true)
} 
