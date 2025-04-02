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
    @State private var fleetWorking = ""
    @State private var presentRank = ""
    @State private var company = ""
    
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isRegistering = false
    
    @Query private var users: [User]
    
    private let fleetTypes = ["Container", "Tanker", "Bulk Carrier", "RORO", "Cruise", "Offshore"]
    private let ranks = ["Captain", "Chief Officer", "Second Officer", "Third Officer", "Chief Engineer", "Second Engineer", "Third Engineer", "Fourth Engineer", "Electrical Officer", "Deck Cadet", "Engine Cadet"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Personal Information")) {
                    TextField("Name", text: $name)
                        .autocapitalization(.words)
                    
                    TextField("Surname", text: $surname)
                        .autocapitalization(.words)
                    
                    TextField("Email", text: $email)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                    
                    SecureField("Password", text: $password)
                    
                    SecureField("Confirm Password", text: $confirmPassword)
                    
                    TextField("Mobile Number", text: $mobileNumber)
                        .keyboardType(.phonePad)
                }
                
                Section(header: Text("Professional Information")) {
                    VStack(alignment: .leading) {
                        Text("Company")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("Company Name", text: $company)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    Picker("Fleet Type", selection: $fleetWorking) {
                        Text("Select Fleet").tag("")
                        ForEach(fleetTypes, id: \.self) { fleet in
                            Text(fleet).tag(fleet)
                        }
                    }
                    
                    Picker("Current Rank", selection: $presentRank) {
                        Text("Select Rank").tag("")
                        ForEach(ranks, id: \.self) { rank in
                            Text(rank).tag(rank)
                        }
                    }
                }
                
                Button(action: registerUser) {
                    if isRegistering {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    } else {
                        Text("Register")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(areAllFieldsFilled ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .disabled(!areAllFieldsFilled || isRegistering)
                .listRowInsets(EdgeInsets())
                .padding()
            }
            .navigationTitle("Seafarer Registration")
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
        !name.isEmpty && !surname.isEmpty && !email.isEmpty && 
        !password.isEmpty && !confirmPassword.isEmpty &&
        !mobileNumber.isEmpty && !fleetWorking.isEmpty && !presentRank.isEmpty &&
        !company.isEmpty && password == confirmPassword && isValidEmail(email)
    }
    
    private func registerUser() {
        guard areAllFieldsFilled else {
            alertMessage = "Please fill in all fields"
            showAlert = true
            return
        }
        
        isRegistering = true
        
        // Create user with Firebase Authentication
        FirebaseService.shared.signUp(email: email, password: password) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let user):
                    // Firebase user created successfully
                    // Save the user ID for future reference
                    userId = user.userIdentifier ?? ""
                    
                    // Create user data for Firestore
                    let firebaseUser = User()
                    firebaseUser.userIdentifier = user.userIdentifier
                    firebaseUser.name = name
                    firebaseUser.surname = surname
                    firebaseUser.email = email
                    firebaseUser.mobileNumber = mobileNumber
                    firebaseUser.fleetWorking = fleetWorking
                    firebaseUser.presentRank = presentRank
                    firebaseUser.company = company
                    
                    // Add to SwiftData
                    modelContext.insert(firebaseUser)
                    try? modelContext.save()
                    
                    // Save user profile to Firestore
                    FirebaseService.shared.saveUserProfile(user: firebaseUser) { profileResult in
                        DispatchQueue.main.async {
                            isRegistering = false
                            
                            switch profileResult {
                            case .success(_):
                                // Successfully saved to Firestore
                                isUserRegistered = true
                                
                            case .failure(let error):
                                alertMessage = "Failed to save profile: \(error.localizedDescription)"
                                showAlert = true
                            }
                        }
                    }
                    
                case .failure(let error):
                    isRegistering = false
                    alertMessage = "Registration failed: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
}

#Preview {
    RegisterView()
        .modelContainer(for: User.self, inMemory: true)
} 