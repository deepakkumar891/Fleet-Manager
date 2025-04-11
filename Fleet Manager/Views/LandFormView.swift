import SwiftUI
import SwiftData
import FirebaseFirestore
import FirebaseAuth

struct LandFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]
    @Query private var landAssignments: [LandAssignment]
    
    @AppStorage("userId") private var userId = ""
    @Binding var isPresented: Bool
    
    @State private var dateHome = Date()
    @State private var expectedJoiningDate = Date().addingTimeInterval(60*60*24*30) // Default to 1 month
    @State private var selectedFleetType = AppConstants.fleetTypes[0]
    @State private var lastVessel = ""
    @State private var email = ""
    @State private var mobileNumber = ""
    @State private var isPublic = true
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var company = AppConstants.defaultCompany
    
    @Environment(\.dismiss) private var dismiss
    
    var onSave: (() -> Void)? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Last Vessel Information")) {
                    TextField("Last Vessel", text: $lastVessel)
                    
                    Picker("Fleet Type", selection: $selectedFleetType) {
                        ForEach(AppConstants.fleetTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    
                    TextField("Company", text: $company)
                        .disabled(true)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Date Information")) {
                    DatePicker("Date Home", selection: $dateHome, displayedComponents: .date)
                    DatePicker("Expected Joining Date", selection: $expectedJoiningDate, displayedComponents: .date)
                }
                
                Section(header: Text("Contact Information")) {
                    TextField("Email", text: $email)
                        .disabled(true) // Auto-filled from user profile
                        .foregroundColor(.gray)
                    
                    TextField("Mobile Number", text: $mobileNumber)
                        .disabled(true) // Auto-filled from user profile
                        .foregroundColor(.gray)
                }
                
                Section {
                    Toggle("Make this information public", isOn: $isPublic)
                    
                    Button(action: saveAssignment) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save Assignment")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || lastVessel.isEmpty)
                }
            }
            .navigationTitle("Land Assignment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert(isPresented: $showingError) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                loadUserData()
            }
        }
    }
    
    private func loadUserData() {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        // Load user's email from Firebase Auth
        email = currentUser.email ?? ""
        
        // Load user's profile data from Firestore
        FirebaseService.shared.fetchUserProfile { result in
            switch result {
            case .success(let userData):
                // Properly access dictionary values
                if let fleet = userData["fleetWorking"] as? String, 
                   AppConstants.fleetTypes.contains(fleet) {
                    self.selectedFleetType = fleet
                }
                if let mobile = userData["mobileNumber"] as? String {
                    self.mobileNumber = mobile
                }
            case .failure:
                // Handle error if needed
                break
            }
        }
    }
    
    private func saveAssignment() {
        isSaving = true
        
        guard let user = users.first(where: { $0.userIdentifier == userId }) else {
            errorMessage = "User not found. Please log out and log in again."
            showingError = true
            isSaving = false
            return
        }
        
        // First, delete any existing ship assignments
        if let shipAssignments = user.shipAssignments {
            for assignment in shipAssignments {
                // Delete from local storage
                modelContext.delete(assignment)
                
                // Delete from Firebase
                if let id = assignment.id?.uuidString {
                    FirebaseService.shared.deleteShipAssignment(id: id) { _ in
                        // Continue regardless of the result
                    }
                }
            }
            // Clear the ship assignments array
            user.shipAssignments = []
        }
        
        // Update the user's fleet type to match the form selection
        user.fleetWorking = selectedFleetType
        
        if let existingAssignment = landAssignments.first(where: { $0.user?.userIdentifier == userId }) {
            // Update existing land assignment
            existingAssignment.lastVessel = lastVessel
            existingAssignment.dateHome = dateHome
            existingAssignment.expectedJoiningDate = expectedJoiningDate
            existingAssignment.email = email
            existingAssignment.mobileNumber = mobileNumber
            existingAssignment.company = company
            existingAssignment.isPublic = isPublic
            existingAssignment.fleetType = selectedFleetType
            
            do {
                try modelContext.save()
                
                // First update the user profile to synchronize fleet info
                FirebaseService.shared.saveUserProfile(user: user) { _ in
                    // Then save the land assignment
                    FirebaseService.shared.saveLandAssignment(landAssignment: existingAssignment) { result in
                        self.handleSaveResult(result)
                    }
                }
            } catch {
                errorMessage = "Failed to save: \(error.localizedDescription)"
                showingError = true
                isSaving = false
            }
        } else {
            // Create new land assignment
            let landAssignment = LandAssignment(
                user: user,
                dateHome: dateHome,
                expectedJoiningDate: expectedJoiningDate,
                fleetType: selectedFleetType,
                lastVessel: lastVessel,
                email: email,
                mobileNumber: mobileNumber,
                isPublic: isPublic,
                company: company
            )
            
            modelContext.insert(landAssignment)
            
            user.currentStatus = .onLand
            
            do {
                try modelContext.save()
                
                // First update the user profile to synchronize fleet info
                FirebaseService.shared.saveUserProfile(user: user) { _ in
                    // Then save the land assignment
                    FirebaseService.shared.saveLandAssignment(landAssignment: landAssignment) { result in
                        self.handleSaveResult(result)
                    }
                }
            } catch {
                errorMessage = "Failed to save locally: \(error.localizedDescription)"
                showingError = true
                isSaving = false
            }
        }
    }
    
    private func handleSaveResult(_ result: Result<String, Error>) {
        DispatchQueue.main.async {
            switch result {
            case .success(_):
                // Update the user's status to onLand
                FirebaseService.shared.updateUserStatus(isOnShip: false) { _ in
                    // Continue with other post-save steps regardless of status update result
                    // Call the onSave callback to trigger any additional sync
                    self.onSave?()
                    
                    // Close the form
                    self.isSaving = false
                    self.isPresented = false
                }
                
            case .failure(let error):
                errorMessage = "Failed to save to Firebase: \(error.localizedDescription)"
                showingError = true
                isSaving = false
            }
        }
    }
}

#Preview {
    LandFormView(isPresented: .constant(true))
        .modelContainer(for: [User.self, LandAssignment.self], inMemory: true)
} 
