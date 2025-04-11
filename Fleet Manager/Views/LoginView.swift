import SwiftUI
import SwiftData
import FirebaseAuth

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var showingRegister = false
    @State private var showingForgotPassword = false
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var isLoggingIn = false
    @State private var isSecure = true
    @State private var buttonScale: CGFloat = 1.0
    @State private var showProgress = false
    @State private var progressValue: Double = 0.0
    
    @AppStorage("userId") private var userId = ""
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.1)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 10) {
                        // Logo and Title
                        VStack(spacing: 15) {
                            Image("Icon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 200, height: 200)
                                .foregroundColor(.blue)
                            
                            Text("Shore Pass")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.primary)
                            
                            Text("Seafarer Management Platform")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 10)
                        
                        // Login Form
                        VStack(spacing: 20) {
                            // Email Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    Image(systemName: "envelope")
                                        .foregroundColor(.gray)
                                    
                                    TextField("Enter your email", text: $email)
                                        .textContentType(.emailAddress)
                                        .keyboardType(.emailAddress)
                                        .autocapitalization(.none)
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                            }
                            
                            // Password Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    Image(systemName: "lock")
                                        .foregroundColor(.gray)
                                    
                                    if isSecure {
                                        SecureField("Enter your password", text: $password)
                                    } else {
                                        TextField("Enter your password", text: $password)
                                    }
                                    
                                    Button(action: {
                                        isSecure.toggle()
                                    }) {
                                        Image(systemName: isSecure ? "eye.slash" : "eye")
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                            }
                            
                            // Forgot Password Button
                            Button(action: { showingForgotPassword = true }) {
                                Text("Forgot Password?")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 1)
                            
                            // Login Button
                            Button(action: {
                                // Start button press animation
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    buttonScale = 0.95
                                }
                                
                                // Reset scale after animation
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                        buttonScale = 1.0
                                    }
                                }
                                
                                // Start login process
                                loginUser()
                            }) {
                                ZStack {
                                    if isLoggingIn {
                                        HStack {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            Text("Logging in...")
                                                .foregroundColor(.white)
                                                .fontWeight(.semibold)
                                        }
                                    } else {
                                        Text("Login")
                                            .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .disabled(email.isEmpty || password.isEmpty || isLoggingIn)
                            .opacity((email.isEmpty || password.isEmpty || isLoggingIn) ? 0.6 : 1)
                            .scaleEffect(buttonScale)
                            
                            if showProgress {
                                ProgressView(value: progressValue)
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .padding(.top, 10)
                            }
                            
                            // Register Button
                            Button(action: { showingRegister = true }) {
                                HStack {
                                    Text("Don't have an account?")
                                        .foregroundColor(.secondary)
                                    
                                    Text("Register")
                                        .foregroundColor(.blue)
                                        .fontWeight(.semibold)
                                }
                                .font(.subheadline)
                            }
                            .padding(.top, 10)
                            Button(action: {
                                UIApplication.shared.open(URL(string: "https://deepakkumar891.github.io/Website/Privacy-policy-page.html")!, options: [:], completionHandler: nil)
                            }, label: {
                                HStack {
                                    Text("By continuing, you agree to our ")
                                        .foregroundStyle(.gray)
                                        .font(.caption) +
                                    Text("Terms of Service and Privacy Policy.")
                                        .foregroundStyle(.blue)
                                        .font(.caption)
                                }
                            })
                        }
                        .padding(.horizontal, 30)
                        .padding(.vertical, 30)
                        .background(Color(.systemBackground))
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationDestination(isPresented: $showingRegister) {
                RegisterView()
            }
            .sheet(isPresented: $showingForgotPassword) {
                ForgotPasswordView()
            }
            .alert("Login Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func loginUser() {
        guard !email.isEmpty && !password.isEmpty else {
            errorMessage = "Please enter both email and password"
            showingError = true
            return
        }
        
        isLoggingIn = true
        showProgress = true
        progressValue = 0.0
        
        // Simulate progress
        let _ = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if progressValue < 0.9 {
                progressValue += 0.1
            } else {
                timer.invalidate()
            }
        }
        
        // Sign in using Firebase Authentication
        FirebaseService.shared.signIn(email: email, password: password) { result in
            DispatchQueue.main.async {
                // Complete progress
                progressValue = 1.0
                
                // Small delay to show completion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isLoggingIn = false
                    showProgress = false
                    
                    switch result {
                    case .success(let firebaseUserId):
                        // Set user ID in UserDefaults
                        userId = firebaseUserId
                        
                        // Fetch user profile from Firebase
                        FirebaseService.shared.fetchUserProfile { profileResult in
                            DispatchQueue.main.async {
                                switch profileResult {
                                case .success(let userData):
                                    // Create or update local user
                                    if let existingUser = users.first(where: { $0.userIdentifier == firebaseUserId }) {
                                        // Update existing user
                                        updateUser(existingUser, with: userData)
                                    } else {
                                        // Create new user
                                        let newUser = User()
                                        newUser.userIdentifier = firebaseUserId
                                        updateUser(newUser, with: userData)
                                        modelContext.insert(newUser)
                                    }
                                    
                                    // Save changes
                                    do {
                                        try modelContext.save()
                                    } catch {
                                        print("Error saving user data: \(error.localizedDescription)")
                                    }
                                    
                                case .failure(let error):
                                    errorMessage = "Failed to fetch user profile: \(error.localizedDescription)"
                                    showingError = true
                                }
                            }
                        }
                        
                    case .failure(let error):
                        errorMessage = "Login failed: \(error.localizedDescription)"
                        showingError = true
                    }
                }
            }
        }
    }
    
    private func updateUser(_ user: User, with userData: [String: Any]) {
        user.name = userData["name"] as? String
        user.surname = userData["surname"] as? String
        user.email = userData["email"] as? String
        user.mobileNumber = userData["mobileNumber"] as? String
        user.fleetWorking = userData["fleetWorking"] as? String
        user.presentRank = userData["presentRank"] as? String
        user.company = userData["company"] as? String
        
        if let statusString = userData["currentStatus"] as? String,
           let status = UserStatus(rawValue: statusString) {
            user.currentStatus = status
        }
        
        if let isVisible = userData["isProfileVisible"] as? Bool {
            user.isProfileVisible = isVisible
        }
        
        if let showEmail = userData["showEmailToOthers"] as? Bool {
            user.showEmailToOthers = showEmail
        }
        
        if let showPhone = userData["showPhoneToOthers"] as? Bool {
            user.showPhoneToOthers = showPhone
        }
        
        if let photoURL = userData["photoURL"] as? String {
            user.photoURL = photoURL
        }
    }
}

#Preview {
    LoginView()
        .modelContainer(for: [User.self], inMemory: true)
}
