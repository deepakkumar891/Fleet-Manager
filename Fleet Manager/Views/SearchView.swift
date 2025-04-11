import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchTerm = ""
    @State private var searchOption = SearchOption.users
    @State private var isSearching = false
    @State private var foundUsers: [User] = []
    @State private var foundShipAssignments: [ShipAssignment] = []
    @State private var foundLandAssignments: [LandAssignment] = []
    @State private var errorMessage = ""
    @State private var showingError = false
    
    enum SearchOption {
        case users
        case shipAssignments
        case landAssignments
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                // Search options
                Picker("Search Type", selection: $searchOption) {
                    
                    //This feature to be included in coming update
                    
                    //Text("Seafarers").tag(SearchOption.users)
                    Text("On Ship").tag(SearchOption.shipAssignments)
                    Text("On Land").tag(SearchOption.landAssignments)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Search by email, name, or vessel...", text: $searchTerm)
                        .autocapitalization(.none)
                        .keyboardType(.default)
                        .scrollDismissesKeyboard(.immediately)
                    
                    if !searchTerm.isEmpty {
                        Button(action: {
                            searchTerm = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Button(action: performSearch) {
                        Text("Search")
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                    .disabled(searchTerm.isEmpty || isSearching)
                }
                .padding(.horizontal)
                .padding(.bottom)
                
                // Results
                ScrollView {
                    if isSearching {
                        ProgressView("Searching...")
                            .padding()
                    } else {
                        searchResultsView
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Search")
            .alert(isPresented: $showingError) {
                Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
    
    private var searchResultsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch searchOption {
            case .users:
                ForEach(foundUsers, id: \.userIdentifier) { user in
                    userCard(user: user)
                }
                
                if foundUsers.isEmpty && !isSearching && !searchTerm.isEmpty {
                    noResultsView(type: "users")
                }
                
            case .shipAssignments:
                ForEach(foundShipAssignments, id: \.id) { assignment in
                    shipAssignmentCard(assignment: assignment)
                }
                
                if foundShipAssignments.isEmpty && !isSearching && !searchTerm.isEmpty {
                    noResultsView(type: "ship assignments")
                }
                
            case .landAssignments:
                ForEach(foundLandAssignments, id: \.id) { assignment in
                    landAssignmentCard(assignment: assignment)
                }
                
                if foundLandAssignments.isEmpty && !isSearching && !searchTerm.isEmpty {
                    noResultsView(type: "land assignments")
                }
            }
        }
        .padding()
    }
    
    private func userCard(user: User) -> some View {
        VStack(alignment: .leading) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(user.name ?? "") \(user.surname ?? "")")
                        .font(.headline)
                    
                    Text(user.email ?? "")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text(user.presentRank ?? "")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .cornerRadius(4)
                        
                        Text(user.fleetWorking ?? "")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green)
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                // Status indicator
                Circle()
                    .foregroundColor(user.currentStatus == .onShip ? .blue : .green)
                    .frame(width: 12, height: 12)
            }
            
            Text("Status: \(user.currentStatus == .onShip ? "On Ship" : "On Land")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(radius: 1)
    }
    
    private func shipAssignmentCard(assignment: ShipAssignment) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(assignment.shipName ?? "Unknown Vessel")
                    .font(.headline)
                
                Spacer()
                
                Text(assignment.rank ?? "")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(4)
            }
            
            Text("Port: \(assignment.portOfJoining ?? "Unknown")")
                .font(.subheadline)
            
            if let dateOfOnboard = assignment.dateOfOnboard {
                Text("Onboard: \(dateOfOnboard.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
            }
            
            Text("Contract: \(assignment.contractLength) months")
                .font(.caption)
            
            Divider()
            
            HStack {
                Image(systemName: "envelope")
                Text(assignment.email ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Image(systemName: "phone")
                Text(assignment.mobileNumber ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(radius: 1)
    }
    
    private func landAssignmentCard(assignment: LandAssignment) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Last Vessel: \(assignment.lastVessel ?? "Unknown")")
                    .font(.headline)
                
                Spacer()
                
                Text(assignment.fleetType ?? "")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(4)
            }
            
            if let dateHome = assignment.dateHome {
                Text("Came home: \(dateHome.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
            }
            
            if let expectedJoiningDate = assignment.expectedJoiningDate {
                Text("Expected joining: \(expectedJoiningDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            Divider()
            
            HStack {
                Image(systemName: "envelope")
                Text(assignment.email ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Image(systemName: "phone")
                Text(assignment.mobileNumber ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(radius: 1)
    }
    
    private func noResultsView(type: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No matching \(type) found")
                .font(.headline)
            
            Text("Try a different search term")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }
    
    private func performSearch() {
        guard !searchTerm.isEmpty else { return }
        UIApplication.shared.inputView?.endEditing(true)
        isSearching = true
        foundUsers = []
        foundShipAssignments = []
        foundLandAssignments = []
        
        let searchLower = searchTerm.lowercased()
        
        switch searchOption {
        case .users:
            // Search for users by email, name, rank, or company
            FirebaseService.shared.searchUsersByEmail(email: searchTerm) { result in
                DispatchQueue.main.async {
                    isSearching = false
                    
                    switch result {
                    case .success(let users):
                        // Filter users based on search term
                        foundUsers = users.filter { user in
                            let name = (user.name ?? "").lowercased()
                            let surname = (user.surname ?? "").lowercased()
                            let email = (user.email ?? "").lowercased()
                            let rank = (user.presentRank ?? "").lowercased()
                            let company = (user.company ?? "").lowercased()
                            let fleet = (user.fleetWorking ?? "").lowercased()
                            
                            return name.contains(searchLower) ||
                                   surname.contains(searchLower) ||
                                   email.contains(searchLower) ||
                                   rank.contains(searchLower) ||
                                   company.contains(searchLower) ||
                                   fleet.contains(searchLower)
                        }
                    case .failure(let error):
                        errorMessage = "Error searching for users: \(error.localizedDescription)"
                        showingError = true
                    }
                }
            }
            
        case .shipAssignments:
            // Search for public ship assignments with enhanced criteria
            FirebaseService.shared.fetchPublicShipAssignments { result in
                DispatchQueue.main.async {
                    isSearching = false
                    
                    switch result {
                    case .success(let assignments):
                        // Enhanced filtering
                        foundShipAssignments = assignments.filter { assignment in
                            let shipName = assignment.shipName?.lowercased() ?? ""
                            let rank = assignment.rank?.lowercased() ?? ""
                            let portOfJoining = assignment.portOfJoining?.lowercased() ?? ""
                            let company = assignment.company?.lowercased() ?? ""
                            let fleet = assignment.user?.fleetWorking?.lowercased() ?? ""
                            
                            return shipName.contains(searchLower) ||
                                   rank.contains(searchLower) ||
                                   portOfJoining.contains(searchLower) ||
                                   company.contains(searchLower) ||
                                   fleet.contains(searchLower)
                        }
                    case .failure(let error):
                        errorMessage = "Error searching for ship assignments: \(error.localizedDescription)"
                        showingError = true
                    }
                }
            }
            
        case .landAssignments:
            // Search for public land assignments with enhanced criteria
            FirebaseService.shared.fetchPublicLandAssignments { result in
                DispatchQueue.main.async {
                    isSearching = false
                    
                    switch result {
                    case .success(let assignments):
                        // Enhanced filtering
                        foundLandAssignments = assignments.filter { assignment in
                            let fleetType = assignment.fleetType?.lowercased() ?? ""
                            let lastVessel = assignment.lastVessel?.lowercased() ?? ""
                            let company = assignment.company?.lowercased() ?? ""
                            let rank = assignment.user?.presentRank?.lowercased() ?? ""
                            
                            return fleetType.contains(searchLower) ||
                                   lastVessel.contains(searchLower) ||
                                   company.contains(searchLower) ||
                                   rank.contains(searchLower)
                        }
                    case .failure(let error):
                        errorMessage = "Error searching for land assignments: \(error.localizedDescription)"
                        showingError = true
                    }
                }
                
            }
        }
    }
}

#Preview {
    SearchView()
        .modelContainer(for: [User.self, ShipAssignment.self, LandAssignment.self], inMemory: true)
} 
