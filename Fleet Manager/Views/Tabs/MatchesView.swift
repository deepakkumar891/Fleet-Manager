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
    
    // For contact sheet
    @State private var showingContactSheet = false
    @State private var selectedAssignment: ShipAssignment?
    @State private var selectedLandAssignment: LandAssignment?
    @State private var isShipAssignmentSelected = false
    
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
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Showing matches for:")
                                            .font(.callout)
                                            .foregroundColor(.secondary)
                                        
                                        HStack(spacing: 4) {
                                            Image(systemName: "building.2.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                            Text(selectedCompany)
                                                .font(.footnote)
                                                .fontWeight(.medium)
                                        }
                                        
                                        HStack(spacing: 4) {
                                            Image(systemName: "tag.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                            Text("\(selectedFleet) fleet")
                                                .font(.footnote)
                                                .fontWeight(.medium)
                                        }
                                        
                                        HStack(spacing: 4) {
                                            Image(systemName: "calendar")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                            Text(monthName(for: selectedMonth))
                                                .font(.footnote)
                                                .fontWeight(.medium)
                                        }
                                    }
                                }
                            }
                            
                            if let user = currentUser {
                                // Show appropriate assignments based on user's status
                                ForEach(0..<matchedAssignments.count, id: \.self) { index in
                                    if let shipAssignment = matchedAssignments[index] as? ShipAssignment {
                                        matchCard(for: shipAssignment, isShipAssignment: true)
                                    } else if let landAssignment = matchedAssignments[index] as? LandAssignment {
                                        matchCard(for: landAssignment, isShipAssignment: false)
                                    }
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
            .sheet(isPresented: $showingContactSheet) {
                // Use a NavigationView for proper layout and controls
                NavigationView {
                    VStack(spacing: 20) {
                        if isShipAssignmentSelected, let assignment = selectedAssignment {
                            let showEmail = isEmailVisible(assignment)
                            let showPhone = isPhoneVisible(assignment)
                            let userName = assignment.user?.name ?? "Unknown"
                            
                            profileHeader(name: userName)
                            
                            Divider()
                            
                            if !showEmail && !showPhone {
                                noContactInfoView()
                            } else {
                                if showEmail {
                                    ContactItem(icon: "envelope.fill", 
                                               title: "Email", 
                                               value: assignment.email ?? "Not provided")
                                }
                                
                                if showPhone {
                                    ContactItem(icon: "phone.fill", 
                                               title: "Phone", 
                                               value: assignment.mobileNumber ?? "Not provided")
                                }
                            }
                        } else if let assignment = selectedLandAssignment {
                            let showEmail = isEmailVisible(assignment)
                            let showPhone = isPhoneVisible(assignment)
                            let userName = assignment.user?.name ?? "Unknown"
                            
                            profileHeader(name: userName)
                            
                            Divider()
                            
                            if !showEmail && !showPhone {
                                noContactInfoView()
                            } else {
                                if showEmail {
                                    ContactItem(icon: "envelope.fill", 
                                               title: "Email", 
                                               value: assignment.email ?? "Not provided")
                                }
                                
                                if showPhone {
                                    ContactItem(icon: "phone.fill", 
                                               title: "Phone", 
                                               value: assignment.mobileNumber ?? "Not provided")
                                }
                            }
                        } else {
                            Text("Contact information not available")
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .navigationTitle("Contact Details")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarItems(trailing: Button("Dismiss") {
                        showingContactSheet = false
                    })
                }
            }
        }
    }
    
    private func loadInitialCriteria() {
        // Initialize criteria from current user's assignment
        if let user = currentUser {
            selectedFleet = user.fleetWorking ?? ""
            
            // Default company to user's company
            selectedCompany = user.company ?? AppConstants.defaultCompany
            
            if user.currentStatus == .onShip, let shipAssignment = currentShipAssignment {
                // If on ship, use ship assignment company if available
                if let shipCompany = shipAssignment.company, !shipCompany.isEmpty {
                    selectedCompany = shipCompany
                }
                
                // Calculate release month from ship assignment
                if let releaseDate = shipAssignment.expectedReleaseDate {
                    selectedMonth = Calendar.current.component(.month, from: releaseDate)
                }
            } else if user.currentStatus == .onLand, let landAssignment = currentLandAssignment {
                // If on land, use land assignment company if available
                if let landCompany = landAssignment.company, !landCompany.isEmpty {
                    selectedCompany = landCompany
                }
                
                // Use expected joining month for land users
                if let joiningDate = landAssignment.expectedJoiningDate {
                    selectedMonth = Calendar.current.component(.month, from: joiningDate)
                }
            }
            
            print("🔧 Initialized search criteria - Company: '\(selectedCompany)', Fleet: '\(selectedFleet)', Month: \(selectedMonth)")
        }
    }
    
    private var matchFilterSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Matching Criteria")) {
                    if let user = currentUser, user.currentStatus == .onShip, 
                       let shipAssignment = currentShipAssignment,
                       let releaseDate = shipAssignment.expectedReleaseDate {
                        Text("Your contract ends: \(releaseDate.formatted(date: .long, time: .omitted))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let user = currentUser, user.currentStatus == .onLand,
                              let landAssignment = currentLandAssignment,
                              let joiningDate = landAssignment.expectedJoiningDate {
                        Text("Your expected joining date: \(joiningDate.formatted(date: .long, time: .omitted))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Picker("Month", selection: $selectedMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(monthName(for: month)).tag(month)
                        }
                    }
                    
                    TextField("Company", text: $selectedCompany)
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                        .overlay(
                            HStack {
                                Spacer()
                                if !selectedCompany.isEmpty {
                                    Button(action: { selectedCompany = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        )
                    
                    TextField("Fleet Type", text: $selectedFleet)
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                        .overlay(
                            HStack {
                                Spacer()
                                if !selectedFleet.isEmpty {
                                    Button(action: { selectedFleet = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        )
                }
                
                Section {
                    Text("Matching is based on your contract completion date. The system will look for relievers who are available around the time your contract ends.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button(action: {
                        loadInitialCriteria()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Reset to Defaults")
                        }
                    }
                    .foregroundColor(.blue)
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
            print("❌ ERROR: No current user found in findMatches()")
            isLoading = false
            return
        }
        
        print("\n🔍 STARTING MATCH SEARCH")
        print("👤 Current user: \(user.name ?? "") \(user.surname ?? "") (ID: \(user.userIdentifier ?? "unknown"))")
        print("👤 Status: \(user.currentStatus == .onShip ? "On Ship" : "On Land")")
        print("👤 Fleet Working: \(user.fleetWorking ?? "unknown")")
        print("👤 Rank: \(user.presentRank ?? "unknown")")
        print("👤 Company: \(user.company ?? "unknown")")
        
        // Set default values if criteria are not specified
        var searchCompany = selectedCompany
        var searchFleet = selectedFleet
        var searchMonth = selectedMonth
        
        // If criteria not specified, use user's data
        if searchCompany.isEmpty {
            searchCompany = user.company ?? AppConstants.defaultCompany
            print("📊 Using user's company for matching: \(searchCompany)")
        }
        
        if searchFleet.isEmpty {
            searchFleet = user.fleetWorking ?? ""
            print("📊 Using user's fleet for matching: \(searchFleet)")
        }
        
        // For users on land, we'll use exactDate search to find matches within ±15 days of expected joining date
        if user.currentStatus == .onLand, let landAssignment = currentLandAssignment,
           let joiningDate = landAssignment.expectedJoiningDate {
            print("📊 Using land user's expected joining date for tight search window: \(joiningDate.formatted(date: .long, time: .omitted))")
            
            // Use the exactDate parameter for more precise search
            loadMatchesFromFirebase(company: searchCompany, fleet: searchFleet, month: searchMonth, exactDate: joiningDate)
            return
        }
        
        // Calculate search month from assignment if we're on a ship
        if user.currentStatus == .onShip, let shipAssignment = currentShipAssignment,
           let releaseDate = shipAssignment.expectedReleaseDate {
            searchMonth = Calendar.current.component(.month, from: releaseDate)
            print("📊 Using ship release month for matching: \(searchMonth)")
        }
        
        print("✅ Using Firebase matching with criteria - Company: '\(searchCompany)', Fleet: '\(searchFleet)', Month: \(searchMonth)")
        // Use the standard month-based search
        loadMatchesFromFirebase(company: searchCompany, fleet: searchFleet, month: searchMonth)
    }
    
    private func loadMatchesFromFirebase(company: String, fleet: String, month: Int, exactDate: Date? = nil) {
        print("📡 STARTING FIREBASE MATCHING")
        print("🔍 Search criteria - Company: '\(company)', Fleet: '\(fleet)', Month: \(month)")
        if let exactDate = exactDate {
            print("🔍 Using exact date: \(exactDate.formatted(date: .long, time: .omitted)) with ±15 day window")
        }
        
        isLoading = true
        let dispatchGroup = DispatchGroup()
        var shipMatches: [ShipAssignment] = []
        var landMatches: [LandAssignment] = []
        
        if let user = currentUser {
            print("👤 Current user status: \(user.currentStatus == .onShip ? "On Ship" : "On Land")")
        }
        
        // First search for compatible ship assignments
        dispatchGroup.enter()
        print("📡 Starting search for compatible SHIP assignments")
        FirebaseService.shared.searchCompatibleShipmates(
            company: company,
            fleet: fleet, 
            month: month,
            exactDate: exactDate) { result in
            
            defer { dispatchGroup.leave() }
            
            switch result {
            case .success(let assignments):
                // Filter out the current user's assignments
                let filteredAssignments = assignments.filter { $0.userIdentifier != self.userId }
                shipMatches = filteredAssignments
                print("📊 Firebase returned \(assignments.count) ship assignments, \(filteredAssignments.count) after filtering out current user")
                
                // Log the matches
                for assignment in filteredAssignments {
                    print("🚢 Ship match: \(assignment.user?.name ?? "unknown") \(assignment.user?.surname ?? "unknown"), Ship: \(assignment.shipName ?? "unknown"), Rank: \(assignment.rank ?? "unknown")")
                }
                
            case .failure(let error):
                print("❌ ERROR finding ship matches: \(error.localizedDescription)")
            }
        }
        
        // Then search for compatible land assignments
        dispatchGroup.enter()
        print("📡 Starting search for compatible LAND assignments")
        FirebaseService.shared.searchCompatibleLandAssignments(
            company: company,
            fleet: fleet, 
            month: month,
            exactDate: exactDate) { result in
            
            defer { dispatchGroup.leave() }
            
            switch result {
            case .success(let assignments):
                // Filter out the current user's assignments
                let filteredAssignments = assignments.filter { $0.userIdentifier != self.userId }
                landMatches = filteredAssignments
                print("📊 Firebase returned \(assignments.count) land assignments, \(filteredAssignments.count) after filtering out current user")
                
                // Log the matches
                for assignment in filteredAssignments {
                    print("🏠 Land match: \(assignment.user?.name ?? "unknown") \(assignment.user?.surname ?? "unknown"), Fleet: \(assignment.fleetType ?? "unknown"), Joining: \(assignment.expectedJoiningDate?.formatted(date: .abbreviated, time: .omitted) ?? "unknown")")
                }
                
            case .failure(let error):
                print("❌ ERROR finding land matches: \(error.localizedDescription)")
            }
        }
        
        // When both searches are complete, combine the results
        dispatchGroup.notify(queue: .main) {
            // Combine the matches based on user status
            if let user = self.currentUser {
                // Appropriate assignments go first
                if user.currentStatus == .onShip {
                    // User on ship, show land matches first
                    self.matchedAssignments = landMatches + shipMatches
                } else {
                    // User on land, show ship matches first
                    self.matchedAssignments = shipMatches + landMatches
                }
            } else {
                self.matchedAssignments = shipMatches + landMatches
            }
            
            self.isLoading = false
            
            // Log final results
            print("📊 MATCHING COMPLETED: \(self.matchedAssignments.count) total matches found")
            print("🚢 Ship matches: \(shipMatches.count)")
            print("🏠 Land matches: \(landMatches.count)")
            
            if self.matchedAssignments.isEmpty {
                print("⚠️ No matches found. Checking search criteria:")
                print("Company: '\(company)'")
                print("Fleet: '\(fleet)'") 
                print("Month: \(month)")
            }
        }
    }
    
    @ViewBuilder
    private func matchCard(for assignment: Any, isShipAssignment: Bool) -> some View {
        let isProfileVisible = isAssignmentVisible(assignment)
        
        VStack(alignment: .leading, spacing: 0) {
            // Header with badge indicating assignment type
            HStack {
                // Icon and type indicator
                HStack(spacing: 6) {
                    Image(systemName: isShipAssignment ? "ferry.fill" : "house.fill")
                        .foregroundColor(.white)
                    
                    Text(isShipAssignment ? "SHIP" : "LAND")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isShipAssignment ? Color.blue : Color.green)
                .cornerRadius(15)
                
                Spacer()
                
                // Contact button - only show if profile is visible
                if isProfileVisible {
                    Button(action: {
                        if isShipAssignment, let shipAssignment = assignment as? ShipAssignment {
                            self.selectedAssignment = shipAssignment
                            self.isShipAssignmentSelected = true
                            self.showingContactSheet = true
                        } else if let landAssignment = assignment as? LandAssignment {
                            self.selectedLandAssignment = landAssignment
                            self.isShipAssignmentSelected = false
                            self.showingContactSheet = true
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 12))
                            Text("Contact")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(15)
                    }
                } else {
                    // Show private badge
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                        Text("Private")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.gray)
                    .cornerRadius(15)
                }
            }
            .padding(.horizontal)
            .padding(.top)
            
            Divider()
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            if !isProfileVisible {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("This profile is private")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("The user has chosen not to share their details")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 30)
                    Spacer()
                }
            } else {
                // Main content
                VStack(alignment: .leading, spacing: 15) {
                    // Person info
                    HStack(alignment: .top) {
                        // Profile image placeholder
                        ZStack {
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: "person.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.gray)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            if isShipAssignment, let shipAssignment = assignment as? ShipAssignment,
                               let user = shipAssignment.user {
                                Text(user.name ?? "Unknown")
                                    .font(.headline)
                                
                                let rank = shipAssignment.rank ?? user.presentRank ?? "Unknown"
                                HStack(spacing: 4) {
                                    Image(systemName: "person.text.rectangle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                    Text("Rank: \(rank)")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                }
                            } else if let landAssignment = assignment as? LandAssignment,
                                    let user = landAssignment.user {
                                Text(user.name ?? "Unknown")
                                    .font(.headline)
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "person.text.rectangle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                    Text("Rank: \(user.presentRank ?? "Unknown")")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                        .padding(.leading, 8)
                        
                        Spacer()
                    }
                    
                    // Assignment details
                    VStack(alignment: .leading, spacing: 8) {
                        if isShipAssignment, let shipAssignment = assignment as? ShipAssignment {
                            timelineInfo(
                                icon: "calendar.badge.clock",
                                title: "Expected release",
                                date: shipAssignment.expectedReleaseDate,
                                color: .blue
                            )
                            
                            infoRow(
                                icon: "ferry.fill", 
                                label: "Ship", 
                                value: shipAssignment.shipName ?? "Unknown",
                                color: .blue
                            )
                            
                            infoRow(
                                icon: "building.2.fill", 
                                label: "Company", 
                                value: shipAssignment.company ?? shipAssignment.user?.company ?? "Unknown",
                                color: .secondary
                            )
                            
                            infoRow(
                                icon: "tag.fill", 
                                label: "Fleet", 
                                value: shipAssignment.user?.fleetWorking ?? "Unknown",
                                color: .secondary
                            )
                        } else if let landAssignment = assignment as? LandAssignment {
                            timelineInfo(
                                icon: "calendar.badge.clock",
                                title: "Available from",
                                date: landAssignment.expectedJoiningDate,
                                color: .green
                            )
                            
                            infoRow(
                                icon: "ferry.fill", 
                                label: "Last vessel", 
                                value: landAssignment.lastVessel ?? "Unknown",
                                color: .green
                            )
                            
                            infoRow(
                                icon: "building.2.fill", 
                                label: "Company", 
                                value: landAssignment.company ?? landAssignment.user?.company ?? "Unknown",
                                color: .secondary
                            )
                            
                            infoRow(
                                icon: "tag.fill", 
                                label: "Fleet", 
                                value: landAssignment.fleetType ?? landAssignment.user?.fleetWorking ?? "Unknown",
                                color: .secondary
                            )
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
        .padding(.vertical, 5)
    }
    
    // Check if an assignment should be visible based on privacy settings
    private func isAssignmentVisible(_ assignment: Any) -> Bool {
        // Get the assignment's user
        let assignmentUser: User?
        if let shipAssignment = assignment as? ShipAssignment {
            assignmentUser = shipAssignment.user
        } else if let landAssignment = assignment as? LandAssignment {
            assignmentUser = landAssignment.user
        } else {
            return false
        }
        
        // If the user has opted to hide their profile, respect that
        if let assignmentUser = assignmentUser, !assignmentUser.isProfileVisible {
            return false
        }
        
        // Reciprocal privacy: If the current user has hidden their profile,
        // they shouldn't see other profiles either
        if let currentUser = currentUser, !currentUser.isProfileVisible {
            return false
        }
        
        return true
    }
    
    // Add this function to check if email should be visible
    private func isEmailVisible(_ assignment: Any) -> Bool {
        if !isAssignmentVisible(assignment) {
            return false
        }
        
        // Check assignment user's email visibility setting
        let showEmail: Bool
        if let shipAssignment = assignment as? ShipAssignment, let user = shipAssignment.user {
            showEmail = user.showEmailToOthers
        } else if let landAssignment = assignment as? LandAssignment, let user = landAssignment.user {
            showEmail = user.showEmailToOthers
        } else {
            return false
        }
        
        // Reciprocal privacy for email
        if let currentUser = currentUser, !currentUser.showEmailToOthers {
            return false 
        }
        
        return showEmail
    }
    
    // Add this function to check if phone should be visible
    private func isPhoneVisible(_ assignment: Any) -> Bool {
        if !isAssignmentVisible(assignment) {
            return false
        }
        
        // Check assignment user's phone visibility setting
        let showPhone: Bool
        if let shipAssignment = assignment as? ShipAssignment, let user = shipAssignment.user {
            showPhone = user.showPhoneToOthers
        } else if let landAssignment = assignment as? LandAssignment, let user = landAssignment.user {
            showPhone = user.showPhoneToOthers
        } else {
            return false
        }
        
        // Reciprocal privacy for phone
        if let currentUser = currentUser, !currentUser.showPhoneToOthers {
            return false 
        }
        
        return showPhone
    }
    
    // Helper view for timeline/date information
    private func timelineInfo(icon: String, title: String, date: Date?, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(title + ":")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(date?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
    
    // Helper view for information rows
    private func infoRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(label + ":")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
    
    // Helper function for profile header in contact sheet
    private func profileHeader(name: String) -> some View {
        VStack {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text(name)
                .font(.title)
                .bold()
                .padding(.bottom, 5)
        }
    }
    
    // Helper function to show when no contact info is available
    private func noContactInfoView() -> some View {
        VStack(spacing: 15) {
            Image(systemName: "eye.slash")
                .font(.system(size: 30))
                .foregroundColor(.gray)
            
            Text("Contact information is private")
                .font(.headline)
                .foregroundColor(.gray)
            
            Text("This user has chosen not to share their contact details.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 30)
    }
    
    // ContactItem view for displaying contact information
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
}

#Preview {
    MatchesView()
        .modelContainer(for: [User.self, ShipAssignment.self, LandAssignment.self], inMemory: true)
} 
