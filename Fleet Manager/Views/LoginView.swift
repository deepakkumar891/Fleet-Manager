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
    
    @AppStorage("userId") private var userId = ""
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            VStack {
                // Logo
                Image(systemName: "ferry")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.blue)
                    .padding(.bottom, 30)
                
                Text("Fleet Manager")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 50)
                
                // Login Form
                VStack(spacing: 20) {
                    TextField("Email", text: $email)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    
                    SecureField("Password", text: $password)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    
                    Button(action: loginUser) {
                        if isLoggingIn {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        } else {
                            Text("Login")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .disabled(email.isEmpty || password.isEmpty || isLoggingIn)
                    
                    HStack {
                        Button(action: { showingRegister = true }) {
                            Text("New User? Register")
                                .foregroundColor(.blue)
                        }
                        
                        Spacer()
                        
                        Button(action: { showingForgotPassword = true }) {
                            Text("Forgot Password?")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.top)
                }
                .padding(.horizontal, 30)
                
                Spacer()
            }
            .padding()
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
        isLoggingIn = true
        
        // Sign in using Firebase Authentication
        FirebaseService.shared.signIn(email: email, password: password) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let firebaseUserId):
                    // Set user ID in UserDefaults
                    userId = firebaseUserId
                    isLoggingIn = false
                    
                    // Don't need to check or load local user data, ContentView will handle that
                    
                case .failure(let error):
                    isLoggingIn = false
                    errorMessage = "Login failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }
}

#Preview {
    LoginView()
        .modelContainer(for: [User.self], inMemory: true)
}