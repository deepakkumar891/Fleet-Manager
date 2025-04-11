import SwiftUI
import SwiftData
import FirebaseFirestore

struct ShipFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]
    @Query private var shipAssignments: [ShipAssignment]
    
    @AppStorage("userId") private var userId = ""
    @Binding var isPresented: Bool
    
    @State private var shipName = ""
    @State private var company = AppConstants.defaultCompany
    @State private var contractLength = 6
    @State private var rank = ""
    @State private var dateOfOnboard = Date()
    @State private var portOfJoining = ""
    @State private var email = ""
    @State private var mobileNumber = ""
    @State private var isPublic = true
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var selectedFleetType = AppConstants.fleetTypes[0]
    
    // Same rank list as in RegisterView
    private let ranks = ["Captain", "Chief Officer", "Second Officer", "Third Officer", "Chief Engineer", "Second Engineer", "Third Engineer", "Fourth Engineer", "Electrical Officer", "Deck Cadet", "Engine Cadet","Bosun","AB","OS","Oiler","Wiper","MotorMan","Fitter","Chief Cook","MSMN","Other"]
    
    var onSave: (() -> Void)? = nil
    
    var currentUser: User? {
        users.first(where: { $0.userIdentifier == userId })
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Ship Assignment Details")) {
                    TextField("Ship Name", text: $shipName)
                    
                    TextField("Company", text: $company)
                        .disabled(true)
                        .foregroundColor(.secondary)
                    
                    Stepper("Contract Length: \(contractLength) months", value: $contractLength, in: 1...24)
                    
                    Picker("Rank", selection: $rank) {
                        Text("Select Rank").tag("")
                        ForEach(ranks, id: \.self) { rankOption in
                            Text(rankOption).tag(rankOption)
                        }
                    }
                    
                    DatePicker("Date of Joining", 
                              selection: $dateOfOnboard,
                              displayedComponents: .date)
                    
                    TextField("Port of Joining", text: $portOfJoining)
                    
                    Picker("Fleet Type", selection: $selectedFleetType) {
                        ForEach(AppConstants.fleetTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                }
                
                Section(header: Text("Contact Details")) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disabled(true)
                    
                    TextField("Mobile Number", text: $mobileNumber)
                        .keyboardType(.phonePad)
                        .disabled(true)
                }
                
                Section(header: Text("Privacy")) {
                    Toggle("Make Public to Fleet Managers", isOn: $isPublic)
                }
            }
            .navigationTitle("Ship Assignment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: saveAssignment) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(shipName.isEmpty || company.isEmpty || rank.isEmpty || portOfJoining.isEmpty || isSaving)
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
                if let user = currentUser {
                    email = user.email ?? ""
                    mobileNumber = user.mobileNumber ?? ""
                    // Set rank from user's profile if it exists
                    if rank.isEmpty {
                        rank = user.presentRank ?? ""
                    }
                    
                    // Set fleet type from user's profile if it exists
                    if let fleetWorking = user.fleetWorking, !fleetWorking.isEmpty,
                       AppConstants.fleetTypes.contains(fleetWorking) {
                        selectedFleetType = fleetWorking
                    }
                }
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
        
        // First, delete any existing land assignments
        if let landAssignments = user.landAssignments {
            for assignment in landAssignments {
                // Delete from local storage
                modelContext.delete(assignment)
                
                // Delete from Firebase
                if let id = assignment.id?.uuidString {
                    FirebaseService.shared.deleteLandAssignment(id: id) { _ in
                        // Continue regardless of the result
                    }
                }
            }
            // Clear the land assignments array
            user.landAssignments = []
        }
        
        // Update the user's fleet type to match the form selection
        user.fleetWorking = selectedFleetType
        
        if let existingAssignment = shipAssignments.first(where: { $0.user?.userIdentifier == userId }) {
            // Update existing ship assignment
            existingAssignment.shipName = shipName
            existingAssignment.portOfJoining = portOfJoining
            existingAssignment.contractLength = contractLength
            existingAssignment.dateOfOnboard = dateOfOnboard
            existingAssignment.company = company
            existingAssignment.fleetType = selectedFleetType
            existingAssignment.mobileNumber = mobileNumber
            existingAssignment.email = email
            existingAssignment.isPublic = isPublic
            
            do {
                try modelContext.save()
                
                // First update the user profile to synchronize fleet info
                FirebaseService.shared.saveUserProfile(user: user) { _ in
                    // Then save the ship assignment
                    FirebaseService.shared.saveShipAssignment(shipAssignment: existingAssignment) { result in
                        DispatchQueue.main.async {
                            self.handleSaveResult(result)
                        }
                    }
                }
            } catch {
                errorMessage = "Failed to save locally: \(error.localizedDescription)"
                showingError = true
                isSaving = false
            }
        } else {
            // Create new ship assignment
            let shipAssignment = ShipAssignment(
                user: user,
                dateOfOnboard: dateOfOnboard,
                rank: rank,
                shipName: shipName,
                company: company,
                contractLength: contractLength,
                portOfJoining: portOfJoining,
                email: email,
                mobileNumber: mobileNumber,
                isPublic: isPublic,
                fleetWorking: selectedFleetType
            )
            
            modelContext.insert(shipAssignment)
            
            user.currentStatus = .onShip
            
            do {
                try modelContext.save()
                
                // First update the user profile to synchronize fleet info
                FirebaseService.shared.saveUserProfile(user: user) { _ in
                    // Then save the ship assignment
                    FirebaseService.shared.saveShipAssignment(shipAssignment: shipAssignment) { result in
                        DispatchQueue.main.async {
                            self.handleSaveResult(result)
                        }
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
                // Update the user's status to onShip
                FirebaseService.shared.updateUserStatus(isOnShip: true) { _ in
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
    ShipFormView(isPresented: .constant(true))
        .modelContainer(for: [User.self, ShipAssignment.self], inMemory: true)
} 
