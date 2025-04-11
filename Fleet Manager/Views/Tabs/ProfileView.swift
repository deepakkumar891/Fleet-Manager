import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseFirestore
import PhotosUI

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
    @State private var company = "Anglo Eastern Ship Management"
    
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isLoading = false
    
    @State private var isProfileVisible = true
    @State private var showEmailToOthers = true
    @State private var showPhoneToOthers = true
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: Image?
    @State private var isUploadingPhoto = false
    
    // Status change variables
    @State private var showingStatusSheet = false
    @State private var newStatusIsOnShip = false
    
    // Ship assignment fields for status change
    @State private var shipName = ""
    @State private var portOfJoining = ""
    @State private var contractLength = 6
    @State private var dateOfOnboard = Date()
    
    // Land assignment fields for status change
    @State private var lastVessel = ""
    @State private var dateHome = Date()
    @State private var expectedJoiningDate = Date().addingTimeInterval(60*60*24*30) // Default to 1 month
    
    @State private var showingPhotoUploadError = false
    @State private var photoUploadErrorMessage = ""
    
    @State private var showingSaveSuccess = false
    
    private let fleetTypes = ["Container", "Tanker", "Bulk Carrier", "RORO", "Cruise", "Offshore", "Bulk & Gear","Other"]
    private let ranks = ["Captain", "Chief Officer", "Second Officer", "Third Officer", "Chief Engineer", "Second Engineer", "Third Engineer", "Fourth Engineer", "Electrical Officer", "Deck Cadet", "Engine Cadet","Bosun","AB","OS","Oiler","Wiper","MotorMan","Fitter","Chief Cook","MSMN","Other"]
    
    var currentUser: User? {
        users.first(where: { $0.userIdentifier == userId })
    }
    
    var body: some View {
        NavigationStack {
            if let user = currentUser {
                Form {
                    Section(header: Text("Profile Photo")) {
                        HStack(alignment: .center){
                            Spacer()
                            Image("aircrew")
                                .resizable()
                                .frame(width: 80, height: 80)
                                .foregroundColor(.gray)
                                
                            Spacer()
                        }
                        .padding()
                    }
                            
                            //Change of Image to be implemented in Next Edition.
                            /*
                            if let profileImage = profileImage {
                                profileImage
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            } else if let photoURL = user.photoURL, let url = URL(string: photoURL) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    ProgressView()
                                }
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .frame(width: 100, height: 100)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Text("Change Photo")
                            }
                            .disabled(isUploadingPhoto)
                            */
                Section("User Details", content: {
                    
                    if isEditing {
                        editProfileForm()
                    } else {
                        profileDetails(user: user)
                    }
                
                })
                    
                    Divider()
                    
                    // Privacy Settings Section
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Privacy Settings")
                            .font(.headline)
                            .padding(.bottom, 5)
                        
                        Toggle("Make Profile Visible to Others", isOn: $isProfileVisible)
                            .onChange(of: isProfileVisible, {
                                updatePrivacySettings()
                            })
                        
                        Toggle("Show Email to Others", isOn: $showEmailToOthers)
                            .onChange(of: showEmailToOthers, {
                                updatePrivacySettings()
                            })
                        
                        Toggle("Show Phone Number to Others", isOn: $showPhoneToOthers)
                            .onChange(of: showPhoneToOthers, {
                                updatePrivacySettings()
                            })
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
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
                .onChange(of: selectedPhoto) { newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            profileImage = Image(uiImage: uiImage)
                            uploadPhoto(uiImage)
                        }
                    }
                }
                .onAppear {
                    if let photoURL = user.photoURL, let url = URL(string: photoURL) {
                        loadImage(from: url)
                    }
                    
                    // Initialize status change variables based on current user status
                    newStatusIsOnShip = user.currentStatus == .onShip
                }
                .sheet(isPresented: $showingStatusSheet) {
                    statusChangeSheet()
                }
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
        .alert("Profile Updated", isPresented: $showingSaveSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your profile has been updated in all places including your current assignments")
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
            company = user.company ?? "Anglo Eastern Ship Management"
            
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
                    showingSaveSuccess = true
                    print("✅ Profile updated successfully")
                case .failure(let error):
                    alertMessage = "Failed to save changes: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    private func logOut() {
        do {
            // Sign out from Firebase
            try Auth.auth().signOut()
            
            // Clear UserDefaults
            UserDefaults.standard.removeObject(forKey: "userId")
            UserDefaults.standard.removeObject(forKey: "isUserRegistered")
            
            // Delete all local data
            if let currentUser = currentUser {
                // Delete all assignments
                if let shipAssignments = currentUser.shipAssignments {
                    for assignment in shipAssignments {
                        modelContext.delete(assignment)
                    }
                }
                if let landAssignments = currentUser.landAssignments {
                    for assignment in landAssignments {
                        modelContext.delete(assignment)
                    }
                }
                // Delete the user
                modelContext.delete(currentUser)
                try? modelContext.save()
            }
            
            // Reset the userId to trigger view change
            userId = ""
            
        } catch let error {
            alertMessage = error.localizedDescription
            showAlert = true
        }
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
                
                // Status with change button
                HStack {
                    Text("Status")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(user.currentStatus == .onShip ? "On Ship" : "On Land")
                        .fontWeight(.medium)
                    
                    Button(action: {
                        showChangeStatusSheet()
                    }) {
                        Text("Change")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(15)
            .shadow(radius: 2)
            
            VStack(spacing: 15) {
                // Logout Button
                Button(action: logOut) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Log Out")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }

                // Delete Account Button (no functionality)
                Button(action: {
                    UIApplication.shared.open(URL(string: "https://deepakkumar891.github.io/deletePage/")!)
                    // No functionality
                }) {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.minus")
                        Text("Delete Account")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
        }
    }
    
    private func editProfileForm() -> some View {
        VStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 15) {
                Text("Personal Information")
                    .font(.headline)
                    .padding(.bottom, 5)
                    .foregroundStyle(.blue)
                
                TextField("Name", text: $name)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .foregroundStyle(.blue)
                
                TextField("Surname", text: $surname)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .foregroundStyle(.blue)
                Text("Email Cannot be Changed")
                    .font(.custom("Genova", size: 12))
                    .foregroundStyle(.gray)
                    TextField("Email*", text: $email)
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
                    .foregroundStyle(.blue)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            
            VStack(alignment: .leading, spacing: 15) {
                Text("Professional Information")
                    .font(.headline)
                    .padding(.bottom, 5)
                
                
                Text("Currently we support only AESM")
                    .font(.custom("Genova", size: 12))
                    .foregroundStyle(.gray)
                
                TextField("Anglo Eastern Ship Management", text: $company)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .disabled(true)
                
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
    
    private func uploadPhoto(_ image: UIImage) {
        guard let userId = currentUser?.userIdentifier else { return }
        
        isUploadingPhoto = true
        
        FirebaseService.shared.uploadUserPhoto(userId: userId, image: image) { result in
            DispatchQueue.main.async {
                isUploadingPhoto = false
                
                switch result {
                case .success(let photoURL):
                    if let user = currentUser {
                        user.photoURL = photoURL
                        try? modelContext.save()
                    }
                case .failure(let error):
                    alertMessage = "Failed to upload photo: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    private func loadImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data, let uiImage = UIImage(data: data) {
                DispatchQueue.main.async {
                    profileImage = Image(uiImage: uiImage)
                }
            }
        }.resume()
    }
    
    private func statusChangeSheet() -> some View {
        NavigationView {
            Form {
                Section(header: Text("Change Status")) {
                    Picker("Status", selection: $newStatusIsOnShip) {
                        Text("On Land").tag(false)
                        Text("On Ship").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.vertical, 5)
                }
                
                if let user = currentUser, newStatusIsOnShip != (user.currentStatus == .onShip) {
                    // Only show details if status is actually changing
                    
                    if newStatusIsOnShip {
                        // Ship assignment fields
                        Section(header: Text("Ship Assignment Details")) {
                            TextField("Ship Name", text: $shipName)
                            TextField("Port of Joining", text: $portOfJoining)
                            
                            Picker("Contract Length (months)", selection: $contractLength) {
                                ForEach(1...12, id: \.self) { month in
                                    Text("\(month) months").tag(month)
                                }
                            }
                            
                            DatePicker("Date of Onboard", selection: $dateOfOnboard, displayedComponents: .date)
                        }
                    } else {
                        // Land assignment fields
                        Section(header: Text("Land Assignment Details")) {
                            TextField("Last Vessel", text: $lastVessel)
                            DatePicker("Date Home", selection: $dateHome, displayedComponents: .date)
                            DatePicker("Expected Joining Date", selection: $expectedJoiningDate, displayedComponents: .date)
                        }
                    }
                    
                    Section {
                        Button(action: changeUserStatus) {
                            Text("Save Status Change")
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        .disabled(!isStatusChangeValid())
                    }
                } else {
                    Text("Please select a different status to make changes.")
                        .foregroundColor(.secondary)
                        .italic()
                        .padding()
                }
            }
            .navigationTitle("Change Status")
            .navigationBarItems(trailing: Button("Cancel") {
                showingStatusSheet = false
            })
        }
    }
    
    private func isStatusChangeValid() -> Bool {
        // Validate required fields based on the new status
        if newStatusIsOnShip {
            return !shipName.isEmpty && !portOfJoining.isEmpty
        } else {
            return !lastVessel.isEmpty
        }
    }
    
    private func changeUserStatus() {
        guard let user = currentUser else { return }
        
        isLoading = true
        showingStatusSheet = false
        
        let oldStatus = user.currentStatus
        let newStatus: UserStatus = newStatusIsOnShip ? .onShip : .onLand
        
        if newStatusIsOnShip {
            // Create a new ship assignment
            let shipAssignment = ShipAssignment(
                user: user,
                dateOfOnboard: dateOfOnboard,
                rank: user.presentRank ?? "",
                shipName: shipName,
                company: user.company ?? AppConstants.defaultCompany,
                contractLength: contractLength,
                portOfJoining: portOfJoining,
                email: user.email ?? "",
                mobileNumber: user.mobileNumber ?? "",
                isPublic: true,
                fleetWorking: user.fleetWorking ?? ""
            )
            
            // Update the user's local status
            user.currentStatus = .onShip
            
            // Use the helper function to handle the transition
            FirebaseService.shared.changeUserAssignmentStatus(
                from: oldStatus,
                to: .onShip,
                userId: user.userIdentifier ?? "",
                newAssignment: shipAssignment
            ) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    switch result {
                    case .success:
                        // Reset form fields
                        self.shipName = ""
                        self.portOfJoining = ""
                        
                        // Update local data model
                        do {
                            self.modelContext.insert(shipAssignment)
                            try self.modelContext.save()
                        } catch {
                            self.alertMessage = "Error saving local data: \(error.localizedDescription)"
                            self.showAlert = true
                        }
                        
                    case .failure(let error):
                        self.alertMessage = "Failed to change status: \(error.localizedDescription)"
                        self.showAlert = true
                        
                        // Revert status change locally
                        user.currentStatus = oldStatus
                    }
                }
            }
        } else {
            // Create a new land assignment
            let landAssignment = LandAssignment(
                user: user,
                dateHome: dateHome,
                expectedJoiningDate: expectedJoiningDate,
                fleetType: user.fleetWorking ?? "",
                lastVessel: lastVessel,
                email: user.email ?? "",
                mobileNumber: user.mobileNumber ?? "",
                isPublic: true,
                company: user.company ?? AppConstants.defaultCompany
            )
            
            // Update the user's local status
            user.currentStatus = .onLand
            
            // Use the helper function to handle the transition
            FirebaseService.shared.changeUserAssignmentStatus(
                from: oldStatus,
                to: .onLand,
                userId: user.userIdentifier ?? "",
                newAssignment: landAssignment
            ) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    switch result {
                    case .success:
                        // Reset form fields
                        self.lastVessel = ""
                        
                        // Update local data model
                        do {
                            self.modelContext.insert(landAssignment)
                            try self.modelContext.save()
                        } catch {
                            self.alertMessage = "Error saving local data: \(error.localizedDescription)"
                            self.showAlert = true
                        }
                        
                    case .failure(let error):
                        self.alertMessage = "Failed to change status: \(error.localizedDescription)"
                        self.showAlert = true
                        
                        // Revert status change locally
                        user.currentStatus = oldStatus
                    }
                }
            }
        }
    }
    
    private func showChangeStatusSheet() {
        guard let user = currentUser else { return }
        
        // Initialize with current status
        newStatusIsOnShip = user.currentStatus == .onShip
        
        // Show the sheet
        showingStatusSheet = true
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
