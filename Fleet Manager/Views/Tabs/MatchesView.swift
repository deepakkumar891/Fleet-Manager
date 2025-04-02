import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseFirestore

struct MatchesView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("userId") private var userId = ""
    
    @Query private var users: [User]
    @Query private var shipAssignments: [ShipAssignment]
    @Query private var landAssignments: [LandAssignment]
    
    @State private var isLoading = false
    @State private var lastRefreshTime = Date()
    @State private var matchedAssignments: [Any] = []
    
    // Matching criteria
    @State private var selectedMonth = Calendar.current.component(.month, from: Date())
    @State private var selectedFleet = ""
    @State private var selectedCompany = ""
    
    // For filter sheet
    @State private var showingFilterSheet = false
    
    var currentUser: User? {
        users.first(where: { $0.userIdentifier == userId })
    }
    
    var currentShipAssignment: ShipAssignment? {
        shipAssignments.first(where: { $0.user?.userIdentifier == userId })
    }
    
    var currentLandAssignment: LandAssignment? {
        landAssignments.first(where: { $0.user?.userIdentifier == userId })
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    if isLoading {
                        ProgressView("Finding matches...")
                            .padding()
                    } else if matchedAssignments.isEmpty {
                        ContentUnavailableView(
                            "No Matches Found",
                            systemImage: "person.2.slash",
                            description: Text("We couldn't find any matching seafarers based on your criteria.")
                        )
                    } else {
                        List {
                            Section {
                                if selectedFleet.isEmpty || selectedCompany.isEmpty {
                                    Text("To find better matches, set filter criteria →")
                                        .font(.callout)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Showing matches for \(selectedCompany), \(selectedFleet) fleet in month \(monthName(for: selectedMonth))")
                                        .font(.callout)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let user = currentUser, user.currentStatus == .onShip {
                                // Show land assignments for ship users
                                ForEach(matchedAssignments as? [LandAssignment] ?? [], id: \.id) { landAssignment in
                                    matchCard(for: landAssignment, isShipAssignment: false)
                                }
                            } else {
                                // Show ship assignments for land users
                                ForEach(matchedAssignments as? [ShipAssignment] ?? [], id: \.id) { shipAssignment in
                                    matchCard(for: shipAssignment, isShipAssignment: true)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Find Matches")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingFilterSheet = true }) {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: findMatches) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showingFilterSheet) {
                matchFilterSheet
            }
            .onAppear {
                loadInitialCriteria()
                findMatches()
            }
        }
    }
    
    private func loadInitialCriteria() {
        // Initialize criteria from current user's assignment
        if let user = currentUser {
            selectedFleet = user.fleetWorking ?? ""
            
            if user.currentStatus == .onShip, let shipAssignment = currentShipAssignment {
                selectedCompany = shipAssignment.company ?? ""
            }
        }
    }
    
    private var matchFilterSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Matching Criteria")) {
                    Picker("Month", selection: $selectedMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(monthName(for: month)).tag(month)
                        }
                    }
                    
                    TextField("Company", text: $selectedCompany)
                    
                    TextField("Fleet Type", text: $selectedFleet)
                }
                
                Button(action: {
                    showingFilterSheet = false
                    findMatches()
                }) {
                    Text("Apply Filters")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .listRowInsets(EdgeInsets())
                .padding()
            }
            .navigationTitle("Match Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingFilterSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private func monthName(for month: Int) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM"
        var components = DateComponents()
        components.month = month
        if let date = Calendar.current.date(from: components) {
            return dateFormatter.string(from: date)
        }
        return ""
    }
    
    private func findMatches() {
        isLoading = true
        matchedAssignments = []
        
        guard let user = currentUser else {
            isLoading = false
            return
        }
        
        // Use the same criteria regardless of user's status
        // We'll look for matches by calling the Firebase service, which has our improved matching logic
        if !selectedCompany.isEmpty && !selectedFleet.isEmpty {
            // Enhanced matching
            loadMatchesFromFirebase()
        } else {
            // Local matching with improved algorithm
            performLocalMatching(for: user)
        }
    }
    
    private func performLocalMatching(for user: User) {
        if user.currentStatus == .onShip {
            // If user is on ship, find compatible land assignments
            if let shipAssignment = currentShipAssignment {
                // Find land assignments that match with our ship assignment
                let filteredLandAssignments = landAssignments.filter { landAssignment in
                    // Skip own assignments and non-public ones
                    guard landAssignment.isPublic,
                          landAssignment.user?.userIdentifier != userId,
                          landAssignment.user?.isProfileVisible == true else {
                        return false
                    }
                    
                    // Use the improved matching algorithm
                    return landAssignment.matchesWithShipAssignment(shipAssignment)
                }
                
                matchedAssignments = filteredLandAssignments
            }
        } else {
            // If user is on land, find compatible ship assignments
            if let landAssignment = currentLandAssignment {
                // Find ship assignments that match with our land assignment
                let filteredShipAssignments = shipAssignments.filter { shipAssignment in
                    // Skip own assignments and non-public ones
                    guard shipAssignment.isPublic,
                          shipAssignment.user?.userIdentifier != userId,
                          shipAssignment.user?.isProfileVisible == true else {
                        return false
                    }
                    
                    // Use the improved matching algorithm
                    return landAssignment.matchesWithShipAssignment(shipAssignment)
                }
                
                matchedAssignments = filteredShipAssignments
            }
        }
        
        // Matching is complete
        isLoading = false
    }
    
    private func loadMatchesFromFirebase() {
        // This function now works for both ship and land users
        FirebaseService.shared.searchCompatibleShipmates(
            company: selectedCompany,
            fleet: selectedFleet, 
            month: selectedMonth
        ) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(let assignments):
                    // Filter out the current user's assignments
                    let filteredAssignments = assignments.filter { assignment in
                        return assignment.userIdentifier != self.userId
                    }
                    
                    self.matchedAssignments = filteredAssignments
                case .failure(let error):
                    print("Error finding matches: \(error.localizedDescription)")
                    self.matchedAssignments = []
                }
            }
        }
    }
    
    @ViewBuilder
    private func matchCard(for assignment: Any, isShipAssignment: Bool) -> some View {
        if isShipAssignment, let shipAssignment = assignment as? ShipAssignment {
            shipAssignmentCard(assignment: shipAssignment)
        } else if let landAssignment = assignment as? LandAssignment {
            landAssignmentCard(assignment: landAssignment)
        }
    }
    
    private func shipAssignmentCard(assignment: ShipAssignment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    if let user = assignment.user {
                        Text("\(user.name ?? "") \(user.surname ?? "")")
                            .font(.headline)
                        
                        if user.showEmailToOthers {
                            Text(assignment.email ?? "")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        if user.showPhoneToOthers {
                            Text(assignment.mobileNumber ?? "")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(assignment.rank ?? "")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .cornerRadius(8)
                    
                    if let user = assignment.user {
                        Text(user.fleetWorking ?? "")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green)
                            .cornerRadius(8)
                    }
                }
            }
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Ship: \(assignment.shipName ?? "")")
                        .font(.subheadline)
                    
                    Text("Company: \(assignment.company ?? "")")
                        .font(.subheadline)
                    
                    Text("Port: \(assignment.portOfJoining ?? "")")
                        .font(.caption)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    if let date = assignment.dateOfOnboard {
                        Text("Join: \(date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                    }
                    
                    Text("Contract: \(assignment.contractLength) months")
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    private func landAssignmentCard(assignment: LandAssignment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    if let user = assignment.user {
                        Text("\(user.name ?? "") \(user.surname ?? "")")
                            .font(.headline)
                        
                        if user.showEmailToOthers {
                            Text(assignment.email ?? "")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        if user.showPhoneToOthers {
                            Text(assignment.mobileNumber ?? "")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    if let user = assignment.user {
                        Text(user.presentRank ?? "")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .cornerRadius(8)
                        
                        Text(user.fleetWorking ?? "")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green)
                            .cornerRadius(8)
                    }
                }
            }
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Last Vessel: \(assignment.lastVessel ?? "")")
                        .font(.subheadline)
                    
                    Text("Fleet: \(assignment.fleetType ?? "")")
                        .font(.subheadline)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    if let date = assignment.dateHome {
                        Text("Home since: \(date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                    }
                    
                    if let date = assignment.expectedJoiningDate {
                        Text("Available: \(date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct MatchCardView: View {
    var landAssignment: LandAssignment?
    var shipAssignment: ShipAssignment?
    
    @State private var showingContactSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    if let landAssignment = landAssignment, 
                       let name = landAssignment.user?.name,
                       let surname = landAssignment.user?.surname,
                       let rank = landAssignment.user?.presentRank {
                        
                        Text(name + " " + surname)
                            .font(.headline)
                        
                        Text("Rank: \(rank)")
                            .font(.subheadline)
                        
                        if let expectedDate = landAssignment.expectedJoiningDate {
                            Text("Expected to join: \(expectedDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        if let fleetType = landAssignment.fleetType {
                            Text("Fleet: \(fleetType)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else if let shipAssignment = shipAssignment,
                              let name = shipAssignment.user?.name,
                              let surname = shipAssignment.user?.surname,
                              let rank = shipAssignment.rank {
                        
                        Text(name + " " + surname)
                            .font(.headline)
                        
                        Text("Rank: \(rank)")
                            .font(.subheadline)
                        
                        Text("Expected release: \(shipAssignment.expectedReleaseDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if let shipName = shipAssignment.shipName {
                            Text("Ship: \(shipName)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Button(action: { showingContactSheet = true }) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 30))
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .sheet(isPresented: $showingContactSheet) {
            if let landAssignment = landAssignment, 
               let name = landAssignment.user?.name,
               let surname = landAssignment.user?.surname,
               let email = landAssignment.email,
               let phone = landAssignment.mobileNumber {
                
                ContactSheet(name: name + " " + surname,
                            email: email,
                            phone: phone)
            } else if let shipAssignment = shipAssignment,
                      let name = shipAssignment.user?.name,
                      let surname = shipAssignment.user?.surname,
                      let email = shipAssignment.email,
                      let phone = shipAssignment.mobileNumber {
                
                ContactSheet(name: name + " " + surname,
                            email: email,
                            phone: phone)
            }
        }
    }
}

struct ContactSheet: View {
    let name: String
    let email: String
    let phone: String
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text(name)
                    .font(.title)
                    .bold()
                
                Divider()
                
                ContactItem(icon: "envelope.fill", title: "Email", value: email)
                
                ContactItem(icon: "phone.fill", title: "Phone", value: phone)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Contact Details")
            .navigationBarItems(trailing: Button("Dismiss") {
                dismiss()
            })
        }
    }
}

struct ContactItem: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 30)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.body)
            }
            
            Spacer()
            
            Button(action: {
                if title == "Email" {
                    if let url = URL(string: "mailto:\(value)") {
                        UIApplication.shared.open(url)
                    }
                } else if title == "Phone" {
                    if let url = URL(string: "tel:\(value)") {
                        UIApplication.shared.open(url)
                    }
                }
            }) {
                Image(systemName: title == "Email" ? "envelope.badge.fill" : "phone.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

#Preview {
    MatchesView()
        .modelContainer(for: [User.self, ShipAssignment.self, LandAssignment.self], inMemory: true)
} 