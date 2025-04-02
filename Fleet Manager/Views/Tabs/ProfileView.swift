import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseFirestore

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("userId") private var userId = ""
    @AppStorage("isUserRegistered") private var isUserRegistered = false
    
    @Query private var users: [User]
    
    @State private var isEditing = false
    @State private var name = ""
    @State private var surname = ""
    @State private var email = ""
    @State private var mobileNumber = ""
    @State private var fleetWorking = ""
    @State private var presentRank = ""
    @State private var company = ""
    
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isLoading = false
    
    @State private var isProfileVisible = true
    @State private var showEmailToOthers = true
    @State private var showPhoneToOthers = true
    
    private let fleetTypes = ["Container", "Tanker", "Bulk Carrier", "RORO", "Cruise", "Offshore"]
    private let ranks = ["Captain", "Chief Officer", "Second Officer", "Third Officer", "Chief Engineer", "Second Engineer", "Third Engineer", "Fourth Engineer", "Electrical Officer", "Deck Cadet", "Engine Cadet"]
    
    var currentUser: User? {
        users.first(where: { $0.userIdentifier == userId })
    }
    
    var body: some View {
        NavigationStack {
            if let user = currentUser {
                ScrollView {
                    VStack(spacing: 20) {
                        profileHeader(user: user)
                        
                        if isEditing {
                            editProfileForm()
                        } else {
                            profileDetails(user: user)
                        }
                        
                        Divider()
                        
                        // Privacy Settings Section
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Privacy Settings")
                                .font(.headline)
                                .padding(.bottom, 5)
                            
                            Toggle("Make Profile Visible to Others", isOn: $isProfileVisible)
                                .onChange(of: isProfileVisible) { newValue in
                                    updatePrivacySettings()
                                }
                            
                            Toggle("Show Email to Others", isOn: $showEmailToOthers)
                                .onChange(of: showEmailToOthers) { newValue in
                                    updatePrivacySettings()
                                }
                            
                            Toggle("Show Phone Number to Others", isOn: $showPhoneToOthers)
                                .onChange(of: showPhoneToOthers) { newValue in
                                    updatePrivacySettings()
                                }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                    }
                    .padding()
                }
                .navigationTitle("Profile")
                .toolbar {
                    Button(isEditing ? "Save" : "Edit") {
                        if isEditing {
                            saveChanges()
                        } else {
                            startEditing()
                        }
                    }
                    .disabled(isLoading)
                }
                .alert(alertMessage, isPresented: $showAlert) {
                    Button("OK", role: .cancel) { }
                }
                .overlay(
                    Group {
                        if isLoading {
                            ProgressView()
                                .background(Color.black.opacity(0.3))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .edgesIgnoringSafeArea(.all)
                        }
                    }
                )
            } else {
                ContentUnavailableView(
                    "Profile Not Found",
                    systemImage: "person.slash",
                    description: Text("There was a problem loading your profile information.")
                )
                .toolbar {
                    Button("Log Out") {
                        logOut()
                    }
                }
            }
        }
    }
    
    private func startEditing() {
        if let user = currentUser {
            name = user.name ?? ""
            surname = user.surname ?? ""
            email = user.email ?? ""
            mobileNumber = user.mobileNumber ?? ""
            fleetWorking = user.fleetWorking ?? ""
            presentRank = user.presentRank ?? ""
            company = user.company ?? ""
            
            // Initialize privacy settings from user model
            isProfileVisible = user.isProfileVisible
            showEmailToOthers = user.showEmailToOthers
            showPhoneToOthers = user.showPhoneToOthers
            
            isEditing = true
        }
    }
    
    private func saveChanges() {
        guard let user = currentUser else { return }
        
        // Validate email
        if !isValidEmail(email) {
            alertMessage = "Please enter a valid email address"
            showAlert = true
            return
        }
        
        isLoading = true
        
        // Update local model
        user.name = name
        user.surname = surname
        user.mobileNumber = mobileNumber
        user.fleetWorking = fleetWorking
        user.presentRank = presentRank
        user.company = company
        
        // Update in Firebase
        FirebaseService.shared.saveUserProfile(user: user) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(_):
                    isEditing = false
                case .failure(let error):
                    alertMessage = "Failed to save changes: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    private func logOut() {
        // Sign out from Firebase
        FirebaseService.shared.signOut() //{ result in
//            switch result {
//            case .success:
//                // Clear local user data
//                if let user = currentUser {
//                    modelContext.delete(user)
//                    try? modelContext.save()
//                }
//                
//                // Clear AppStorage
//                UserDefaults.standard.removeObject(forKey: "userId")
//                
//                // Navigate to login view
//                isUserRegistered = false
//                
//            case .failure(let error):
//                errorMessage = "Failed to sign out: \(error.localizedDescription)"
//                showingError = true
//            }
//        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
    
    private func updatePrivacySettings() {
        guard let user = currentUser else { return }
        
        isLoading = true
        
        // Update the user's privacy settings
        user.isProfileVisible = isProfileVisible
        user.showEmailToOthers = showEmailToOthers
        user.showPhoneToOthers = showPhoneToOthers
        
        // Save to Firebase
        FirebaseService.shared.saveUserProfile(user: user) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success:
                    // Successfully saved
                    break
                case .failure(let error):
                    alertMessage = "Failed to update privacy settings: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    private func profileHeader(user: User) -> some View {
        VStack(spacing: 16) {
            // Profile Image
            Image(systemName: "person.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.blue)
                .background(Color.white)
                .clipShape(Circle())
                .shadow(radius: 5)
            
            // Name and Rank
            VStack(spacing: 4) {
                Text("\(user.name ?? "") \(user.surname ?? "")")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(user.presentRank ?? "No Rank")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Status Badge
            HStack {
                Image(systemName: user.currentStatus == .onShip ? "ship.fill" : "house.fill")
                    .foregroundColor(user.currentStatus == .onShip ? .green : .blue)
                Text(user.currentStatus == .onShip ? "On Ship" : "On Land")
                    .font(.subheadline)
                    .foregroundColor(user.currentStatus == .onShip ? .green : .blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(user.currentStatus == .onShip ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
            )
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(radius: 5)
    }
    
    private func profileDetails(user: User) -> some View {
        VStack(spacing: 20) {
            // Personal Information Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Personal Information")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                InfoRow(title: "Email", value: user.email ?? "Not set")
                InfoRow(title: "Mobile", value: user.mobileNumber ?? "Not set")
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(15)
            .shadow(radius: 2)
            
            // Professional Information Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Professional Information")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                InfoRow(title: "Company", value: user.company ?? "Not set")
                InfoRow(title: "Fleet", value: user.fleetWorking ?? "Not set")
                InfoRow(title: "Rank", value: user.presentRank ?? "Not set")
                InfoRow(title: "Status", value: user.currentStatus == .onShip ? "On Ship" : "On Land")
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(15)
            .shadow(radius: 2)
            
            // Logout Button
            Button(action: logOut) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Log Out")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.top)
        }
    }
    
    private func editProfileForm() -> some View {
        VStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 15) {
                Text("Personal Information")
                    .font(.headline)
                    .padding(.bottom, 5)
                
                TextField("Name", text: $name)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                TextField("Surname", text: $surname)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disabled(true) // Email can't be changed in Firebase without re-authentication
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                TextField("Mobile Number", text: $mobileNumber)
                    .keyboardType(.phonePad)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            
            VStack(alignment: .leading, spacing: 15) {
                Text("Professional Information")
                    .font(.headline)
                    .padding(.bottom, 5)
                
                TextField("Company", text: $company)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                VStack(alignment: .leading) {
                    Text("Fleet Type")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("Fleet Type", selection: $fleetWorking) {
                        ForEach(fleetTypes, id: \.self) { fleet in
                            Text(fleet).tag(fleet)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                
                VStack(alignment: .leading) {
                    Text("Current Rank")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("Current Rank", selection: $presentRank) {
                        ForEach(ranks, id: \.self) { rank in
                            Text(rank).tag(rank)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            
            HStack {
                Button(action: { isEditing = false }) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                Button(action: saveChanges) {
                    Text("Save Changes")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding(.top, 10)
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: User.self, inMemory: true)
} 
