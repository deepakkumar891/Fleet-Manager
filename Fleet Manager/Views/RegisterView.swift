import SwiftUI
import SwiftData
import FirebaseAuth

struct RegisterView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("isUserRegistered") private var isUserRegistered = false
    @AppStorage("userId") private var userId = ""
    
    @State private var name = ""
    @State private var surname = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var mobileNumber = ""
    @State private var selectedFleetType = AppConstants.fleetTypes[0]
    @State private var presentRank = ""
    @State private var company = AppConstants.defaultCompany
    @State private var isOnShip = false
    
    // Ship assignment fields
    @State private var shipName = ""
    @State private var portOfJoining = ""
    @State private var contractLength = 6
    @State private var dateOfOnboard = Date()
    
    // Land assignment fields
    @State private var lastVessel = ""
    @State private var dateHome = Date()
    @State private var expectedJoiningDate = Date().addingTimeInterval(60*60*24*30) // Default to 1 month
    
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isRegistering = false
    
    @Query private var users: [User]
    
    private let ranks = ["Captain", "Chief Officer", "Second Officer", "Third Officer", "Chief Engineer", "Second Engineer", "Third Engineer", "Fourth Engineer", "Electrical Officer", "Deck Cadet", "Engine Cadet","Bosun","AB","OS","Oiler","Wiper","MotorMan","Fitter","Chief Cook","MSMN","Other"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Personal Information")) {
                    TextField("Name", text: $name)
                    TextField("Surname", text: $surname)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("Mobile Number", text: $mobileNumber)
                        .keyboardType(.phonePad)
                }
                
                Section(header: Text("Professional Information")) {
                    Picker("Fleet Type", selection: $selectedFleetType) {
                        ForEach(AppConstants.fleetTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    
                    Picker("Present Rank", selection: $presentRank) {
                        Text("Select Rank").tag("")
                        ForEach(ranks, id: \.self) { rank in
                            Text(rank).tag(rank)
                        }
                    }
                    
                    TextField("Company", text: $company)
                        .disabled(true)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Current Status")) {
                    Picker("Status", selection: $isOnShip) {
                        Text("On Land").tag(false)
                        Text("On Ship").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.vertical, 5)
                    
                    if isOnShip {
                        // Ship assignment fields
                        TextField("Ship Name", text: $shipName)
                        TextField("Port of Joining", text: $portOfJoining)
                        
                        Picker("Contract Length (months)", selection: $contractLength) {
                            ForEach(1...12, id: \.self) { month in
                                Text("\(month) months").tag(month)
                            }
                        }
                        
                        DatePicker("Date of Onboard", selection: $dateOfOnboard, displayedComponents: .date)
                    } else {
                        // Land assignment fields
                        TextField("Last Vessel", text: $lastVessel)
                        DatePicker("Date Home", selection: $dateHome, displayedComponents: .date)
                        DatePicker("Expected Joining Date", selection: $expectedJoiningDate, displayedComponents: .date)
                    }
                }
                
                Section(header: Text("Security")) {
                    SecureField("Password", text: $password)
                    SecureField("Confirm Password", text: $confirmPassword)
                }
                
                Section {
                    Button(action: register) {
                        if isRegistering {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Register")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!areAllFieldsFilled || isRegistering)
                }
            }
            .navigationTitle("Register")
            .alert(alertMessage, isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            }
            .overlay(
                ZStack {
                    if isRegistering {
                        Color.black.opacity(0.3)
                            .edgesIgnoringSafeArea(.all)
                        
                        VStack {
                            ProgressView()
                                .scaleEffect(1.5)
                                .padding()
                            Text("Creating your profile...")
                                .foregroundColor(.white)
                                .bold()
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                }
            )
        }
    }
    
    private var areAllFieldsFilled: Bool {
        let baseCondition = !name.isEmpty && !surname.isEmpty && !email.isEmpty && 
            !password.isEmpty && !confirmPassword.isEmpty &&
            !mobileNumber.isEmpty && !presentRank.isEmpty &&
            !company.isEmpty && password == confirmPassword && isValidEmail(email)
        
        if isOnShip {
            return baseCondition && !shipName.isEmpty && !portOfJoining.isEmpty
        } else {
            return baseCondition && !lastVessel.isEmpty
        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
    
    private func register() {
        guard areAllFieldsFilled else { return }
        
        isRegistering = true
        
        // Create user in Firebase Auth
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if let error = error {
                alertMessage = error.localizedDescription
                showAlert = true
                isRegistering = false
                return
            }
            
            guard let user = result?.user else {
                alertMessage = "Failed to create user"
                showAlert = true
                isRegistering = false
                return
            }
            
            // Create user in SwiftData
            let newUser = User(
                name: name,
                surname: surname,
                email: email,
                password: password,
                mobileNumber: mobileNumber,
                fleetWorking: selectedFleetType,
                presentRank: presentRank,
                company: company
            )
            
            // Set the user's status based on selection
            newUser.currentStatus = isOnShip ? .onShip : .onLand
            newUser.userIdentifier = user.uid
            
            modelContext.insert(newUser)
            
            // Save user profile to Firestore
            FirebaseService.shared.saveUserProfile(user: newUser) { result in
                switch result {
                case .success:
                    // Create the appropriate assignment based on status
                    if self.isOnShip {
                        // Create ship assignment
                        let shipAssignment = ShipAssignment(
                            user: newUser,
                            dateOfOnboard: self.dateOfOnboard,
                            rank: self.presentRank,
                            shipName: self.shipName,
                            company: self.company,
                            contractLength: self.contractLength,
                            portOfJoining: self.portOfJoining,
                            email: self.email,
                            mobileNumber: self.mobileNumber,
                            isPublic: true,
                            fleetWorking: self.selectedFleetType
                        )
                        
                        self.modelContext.insert(shipAssignment)
                        
                        // Save to Firebase
                        FirebaseService.shared.saveShipAssignment(shipAssignment: shipAssignment) { assignmentResult in
                            DispatchQueue.main.async {
                                self.isRegistering = false
                                
                                switch assignmentResult {
                                case .success:
                                    self.userId = user.uid
                                    self.isUserRegistered = true
                                case .failure(let error):
                                    self.alertMessage = "Failed to save ship assignment: \(error.localizedDescription)"
                                    self.showAlert = true
                                }
                            }
                        }
                    } else {
                        // Create land assignment
                        let landAssignment = LandAssignment(
                            user: newUser,
                            dateHome: self.dateHome,
                            expectedJoiningDate: self.expectedJoiningDate,
                            fleetType: self.selectedFleetType,
                            lastVessel: self.lastVessel,
                            email: self.email,
                            mobileNumber: self.mobileNumber,
                            isPublic: true,
                            company: self.company
                        )
                        
                        self.modelContext.insert(landAssignment)
                        
                        // Save to Firebase
                        FirebaseService.shared.saveLandAssignment(landAssignment: landAssignment) { assignmentResult in
                            DispatchQueue.main.async {
                                self.isRegistering = false
                                
                                switch assignmentResult {
                                case .success:
                                    self.userId = user.uid
                                    self.isUserRegistered = true
                                case .failure(let error):
                                    self.alertMessage = "Failed to save land assignment: \(error.localizedDescription)"
                                    self.showAlert = true
                                }
                            }
                        }
                    }
                    
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.isRegistering = false
                        self.alertMessage = "Failed to save profile: \(error.localizedDescription)"
                        self.showAlert = true
                    }
                }
            }
        }
    }
}

#Preview {
    RegisterView()
        .modelContainer(for: [User.self], inMemory: true)
} 
