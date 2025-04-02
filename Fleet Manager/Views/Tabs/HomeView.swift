import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("userId") private var userId = ""
    @AppStorage("isUserRegistered") private var isUserRegistered = false
    
    @Query private var users: [User]
    @Query private var shipAssignments: [ShipAssignment]
    @Query private var landAssignments: [LandAssignment]
    
    @State private var showingShipForm = false
    @State private var showingLandForm = false
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    var currentUser: User? {
        users.first(where: { $0.userIdentifier == userId })
    }
    
    var hasShipAssignment: Bool {
        shipAssignments.contains(where: { $0.user?.userIdentifier == userId })
    }
    
    var hasLandAssignment: Bool {
        landAssignments.contains(where: { $0.user?.userIdentifier == userId })
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                if isLoading {
                    ProgressView("Loading...")
                } else if let user = currentUser {
                    ScrollView {
                        VStack(spacing: 20) {
                            // User status card
                            statusCard(user: user)
                            
                            // Action cards
                            if user.currentStatus == .onShip {
                                onShipActionCards()
                            } else {
                                onLandActionCards()
                            }
                            
                            // Current assignment card
                            if user.currentStatus == .onShip {
                                shipAssignmentCard()
                            } else if hasLandAssignment {
                                landAssignmentCard()
                            }
                        }
                        .padding()
                    }
                } else {
                    ContentUnavailableView(
                        "User Not Found",
                        systemImage: "person.slash",
                        description: Text("There was a problem loading your profile information.")
                    )
                }
            }
            .navigationTitle("Dashboard")
            .refreshable {
                refreshData()
            }
            .sheet(isPresented: $showingShipForm) {
                ShipFormView(isPresented: $showingShipForm, onSave: refreshData)
            }
            .sheet(isPresented: $showingLandForm) {
                LandFormView(isPresented: $showingLandForm, onSave: refreshData)
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                refreshData()
            }
        }
    }
    
    private func statusCard(user: User) -> some View {
        VStack(spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome, \(user.name ?? "User")")
                        .font(.title2)
                        .bold()
                    
                    Text("Current Status:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Image(systemName: user.currentStatus == .onShip ? "ferry.fill" : "house.fill")
                            .foregroundColor(user.currentStatus == .onShip ? .blue : .green)
                        
                        Text(user.currentStatus == .onShip ? "On Ship" : "On Land")
                            .font(.headline)
                            .foregroundColor(user.currentStatus == .onShip ? .blue : .green)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    if user.currentStatus == .onShip {
                        showingLandForm = true
                    } else {
                        showingShipForm = true
                    }
                }) {
                    Text(user.currentStatus == .onShip ? "Switch to Land" : "Switch On Board")
                        .fontWeight(.medium)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(user.currentStatus == .onShip ? Color.green : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            
            if user.isProfileVisible {
                HStack {
                    Label("Profile Visible", systemImage: "eye")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    Spacer()
                    
                    if user.showEmailToOthers {
                        Label("Email Visible", systemImage: "envelope")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("Email Hidden", systemImage: "envelope.badge.shield")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if user.showPhoneToOthers {
                        Label("Phone Visible", systemImage: "phone")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("Phone Hidden", systemImage: "iphone.gen2.slash")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 5)
            } else {
                HStack {
                    Label("Profile Hidden", systemImage: "eye.slash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(.top, 5)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
    
    private func onShipActionCards() -> some View {
        VStack(spacing: 15) {
            ActionCard(
                title: "Update Contract Details",
                subtitle: "Change your current ship Contract details",
                icon: "ferry.fill",
                iconColor: .blue,
                action: { showingShipForm = true }
            )
            
            ActionCard(
                title: "Switch to Land Status",
                subtitle: "Record that you've completed your contract",
                icon: "house.fill",
                iconColor: .green,
                action: { showingLandForm = true }
            )
            
            ActionCard(
                title: "Find Replacement",
                subtitle: "Search for potential reliver",
                icon: "person.2.fill",
                iconColor: .orange,
                action: { 
                    // This will take them to the matches tab
                }
            )
        }
    }
    
    private func onLandActionCards() -> some View {
        VStack(spacing: 15) {
            ActionCard(
                title: "Update Land Status",
                subtitle: "Update your availability information",
                icon: "house.fill",
                iconColor: .green,
                action: { showingLandForm = true }
            )
            
            ActionCard(
                title: "Join a Ship",
                subtitle: "Record that you're joining a vessel",
                icon: "ferry.fill",
                iconColor: .blue,
                action: { showingShipForm = true }
            )
            
            ActionCard(
                title: "Find Reliver",
                subtitle: "Search for available Reliver",
                icon: "binoculars.fill",
                iconColor: .orange,
                action: {
                    // This will take them to the matches tab
                }
            )
        }
    }
    
    private func shipAssignmentCard() -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Current Ship Contract")
                .font(.headline)
                .padding(.bottom, 5)
            
            if let assignment = shipAssignments.first(where: { $0.user?.userIdentifier == userId }) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Vessel: \(assignment.shipName ?? "Unknown")")
                            .font(.subheadline)
                        
                        Text("Company: \(assignment.company ?? "Unknown")")
                            .font(.subheadline)
                        
                        Text("Rank: \(assignment.rank ?? "Unknown")")
                            .font(.subheadline)
                        
                        Text("Port of Joining: \(assignment.portOfJoining ?? "Unknown")")
                            .font(.caption)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 5) {
                        if let onboardDate = assignment.dateOfOnboard {
                            Text("Joined: \(onboardDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                        }
                        
                        Text("Contract: \(assignment.contractLength) months")
                            .font(.caption)
                        
                        Text("Expected Release: \(assignment.expectedReleaseDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                Text("Status: \(assignment.isPublic ? "Public" : "Private")")
                    .font(.caption)
                    .foregroundColor(assignment.isPublic ? .green : .secondary)
                    .padding(.top, 5)
            } else {
                Text("No Contract found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button(action: { showingShipForm = true }) {
                    Text("Add Contract")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
    
    private func landAssignmentCard() -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Current Land Status")
                .font(.headline)
                .padding(.bottom, 5)
            
            if let assignment = landAssignments.first(where: { $0.user?.userIdentifier == userId }) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Last Vessel: \(assignment.lastVessel ?? "Unknown")")
                            .font(.subheadline)
                        
                        Text("Fleet Type: \(assignment.fleetType ?? "Unknown")")
                            .font(.subheadline)
                        
                        if let homeDate = assignment.dateHome {
                            Text("Home Since: \(homeDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 5) {
                        if let expectedDate = assignment.expectedJoiningDate {
                            Text("Available from: \(expectedDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Text("Status: \(assignment.isPublic ? "Public" : "Private")")
                    .font(.caption)
                    .foregroundColor(assignment.isPublic ? .green : .secondary)
                    .padding(.top, 5)
            } else {
                Text("No land Status found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button(action: { showingLandForm = true }) {
                    Text("Add Land Status")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
    
    private func refreshData() {
        isLoading = true
        
        // Fetch current user profile from Firebase
        FirebaseService.shared.fetchUserProfile { result in
            switch result {
            case .success(let userData):
                // Update local user data if needed
                if let user = currentUser {
                    if let name = userData["name"] as? String { user.name = name }
                    if let surname = userData["surname"] as? String { user.surname = surname }
                    if let email = userData["email"] as? String { user.email = email }
                    if let mobile = userData["mobileNumber"] as? String { user.mobileNumber = mobile }
                    if let fleet = userData["fleetWorking"] as? String { user.fleetWorking = fleet }
                    if let rank = userData["presentRank"] as? String { user.presentRank = rank }
                    if let statusString = userData["currentStatus"] as? String,
                       let status = UserStatus(rawValue: statusString) {
                        user.currentStatus = status
                    }
                    if let isVisible = userData["isProfileVisible"] as? Bool { user.isProfileVisible = isVisible }
                    if let showEmail = userData["showEmailToOthers"] as? Bool { user.showEmailToOthers = showEmail }
                    if let showPhone = userData["showPhoneToOthers"] as? Bool { user.showPhoneToOthers = showPhone }
                    
                    try? modelContext.save()
                }
                
                // Fetch assignments based on user status
                if currentUser?.currentStatus == .onShip {
                    fetchShipAssignments()
                } else {
                    fetchLandAssignments()
                }
                
            case .failure(let error):
                // If profile not found, create a new one with default values
                if (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == "User profile not found" {
                    createDefaultUserProfile()
                } else {
                    DispatchQueue.main.async {
                        alertTitle = "Error"
                        alertMessage = "Failed to load profile: \(error.localizedDescription)"
                        showAlert = true
                        isLoading = false
                    }
                }
            }
        }
    }
    
    private func createDefaultUserProfile() {
        guard let currentUser = Auth.auth().currentUser else {
            isLoading = false
            return
        }
        
        // Create a new user in SwiftData
        let newUser = User()
        newUser.userIdentifier = currentUser.uid
        newUser.email = currentUser.email
        newUser.name = "New User"  // Default name
        newUser.isProfileVisible = true
        newUser.showEmailToOthers = true
        newUser.showPhoneToOthers = true
        
        // Insert into local context
        modelContext.insert(newUser)
        try? modelContext.save()
        
        // Make sure userId is stored in UserDefaults
        UserDefaults.standard.set(currentUser.uid, forKey: "userId")
        userId = currentUser.uid  // Update the app storage value
        
        // Create user profile in Firebase
        FirebaseService.shared.saveUserProfile(user: newUser) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(_):
                    print("Successfully created default profile")
                    // Wait a moment to ensure Firebase has processed the write
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.refreshData()
                    }
                    
                case .failure(let error):
                    self.alertTitle = "Error"
                    self.alertMessage = "Failed to create profile: \(error.localizedDescription)"
                    self.showAlert = true
                }
            }
        }
    }
    
    private func fetchShipAssignments() {
        guard let userId = FirebaseService.shared.getCurrentUserId() else {
            isLoading = false
            return
        }
        
        FirebaseService.shared.fetchUserShipAssignments(userId: userId) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(_):
                    // Data is automatically synced with SwiftData
                    break
                    
                case .failure(let error):
                    alertTitle = "Error"
                    alertMessage = "Failed to load ship assignments: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    private func fetchLandAssignments() {
        guard let userId = FirebaseService.shared.getCurrentUserId() else {
            isLoading = false
            return
        }
        
        FirebaseService.shared.fetchUserLandAssignments(userId: userId) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(_):
                    // Data is automatically synced with SwiftData
                    break
                    
                case .failure(let error):
                    alertTitle = "Error"
                    alertMessage = "Failed to load land assignments: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
}

struct ActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(iconColor)
                    .frame(width: 40, height: 40)
                    .padding(.trailing, 10)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(15)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [User.self, ShipAssignment.self, LandAssignment.self], inMemory: true)
} 
