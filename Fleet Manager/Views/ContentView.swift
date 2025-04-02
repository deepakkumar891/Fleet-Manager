import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAuth

struct ContentView: View {
    @AppStorage("userId") private var userId = ""
    @State private var isCheckingAuth = false
    @State private var showAuthError = false
    @State private var errorMessage = ""
    
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]
    
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
                    isCheckingAuth = false
                    
                case .failure(let error):
                    print("Failed to fetch user profile: \(error.localizedDescription)")
                    errorMessage = "Could not retrieve your profile. Please sign in again."
                    showAuthError = true
                }
            }
        }
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
}

#Preview {
    ContentView()
        .modelContainer(for: [User.self, ShipAssignment.self, LandAssignment.self], inMemory: true)
} 
