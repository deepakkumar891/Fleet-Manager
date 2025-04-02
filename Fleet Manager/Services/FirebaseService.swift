//
//  FirebaseService.swift
//  Fleet Manager
//
//  Created by Deepak Kumar on 31/03/2025.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftData

class FirebaseService {
    static let shared = FirebaseService()
    
    private let db = Firestore.firestore()
    
    private init() {
        // Configure Firestore settings
        let settings = FirestoreSettings()
        // Don't enable persistence for offline caching
        settings.isPersistenceEnabled = false
        db.settings = settings
    }
    
    // MARK: - Authentication
    
    func isUserSignedIn() -> Bool {
        return Auth.auth().currentUser != nil
    }
    
    func getCurrentUserId() -> String? {
        return Auth.auth().currentUser?.uid
    }
    
    func signUp(email: String, password: String, completion: @escaping (Result<User, Error>) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { authResult, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let authResult = authResult else {
                completion(.failure(NSError(domain: "FirebaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown authentication error"])))
                return
            }
            
            // Create new user
            let newUser = User()
            newUser.email = email
            newUser.userIdentifier = authResult.user.uid
            
            // Save user ID to UserDefaults
            UserDefaults.standard.set(authResult.user.uid, forKey: "userId")
            
            completion(.success(newUser))
        }
    }
    
    func signIn(email: String, password: String, completion: @escaping (Result<String, Error>) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { authResult, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let userId = authResult?.user.uid else {
                completion(.failure(NSError(domain: "FirebaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown authentication error"])))
                return
            }
            
            // Save user ID to UserDefaults
            UserDefaults.standard.set(userId, forKey: "userId")
            
            completion(.success(userId))
        }
    }
    
    func signOut() -> Result<Void, Error> {
        do {
            try Auth.auth().signOut()
            // Clear UserDefaults
            UserDefaults.standard.removeObject(forKey: "userId")
            return .success(())
        } catch {
            return .failure(error)
        }
    }
    
    func resetPassword(email: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Auth.auth().sendPasswordReset(withEmail: email) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    // MARK: - User Profile
    
    func saveUserProfile(user: User, completion: @escaping (Result<String, Error>) -> Void) {
        guard let userId = user.userIdentifier else {
            completion(.failure(NSError(domain: "FirebaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User has no identifier"])))
            return
        }
        
        // Create user data dictionary
        let userData: [String: Any] = [
            "email": user.email ?? "",
            "name": user.name ?? "",
            "surname": user.surname ?? "",
            "mobileNumber": user.mobileNumber ?? "",
            "fleetWorking": user.fleetWorking ?? "",
            "presentRank": user.presentRank ?? "",
            "currentStatus": user.currentStatus.rawValue,
            "isProfileVisible": user.isProfileVisible,
            "showEmailToOthers": user.showEmailToOthers,
            "showPhoneToOthers": user.showPhoneToOthers
        ]
        
        // Save to Firestore - using userId as the document ID
        db.collection("users").document(userId).setData(userData) { error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            completion(.success(userId))
        }
    }
    
    func updateUserStatus(isOnShip: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = getCurrentUserId() else {
            completion(.failure(NSError(domain: "FirebaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])))
            return
        }
        
        // Update only the status field in the user document
        let newStatus = isOnShip ? UserStatus.onShip.rawValue : UserStatus.onLand.rawValue
        
        db.collection("users").document(userId).updateData([
            "currentStatus": newStatus
        ]) { error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            completion(.success(()))
        }
    }
    
    func fetchUserProfile(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let userId = getCurrentUserId() else {
            completion(.failure(NSError(domain: "FirebaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])))
            return
        }

        // Using userId as document ID
        db.collection("users").document(userId).getDocument { document, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let document = document, document.exists, let data = document.data() else {
                completion(.failure(NSError(domain: "FirebaseService", code: 2, userInfo: [NSLocalizedDescriptionKey: "User profile not found"])))
                return
            }
            
            completion(.success(data))
        }
    }
    
    // MARK: - Ship Assignments
    
    func saveShipAssignment(shipAssignment: ShipAssignment, completion: @escaping (Result<String, Error>) -> Void) {
        guard let userIdentifier = shipAssignment.userIdentifier else {
            completion(.failure(NSError(domain: "FirebaseService", code: 3, userInfo: [NSLocalizedDescriptionKey: "User identifier missing"])))
            return
        }
        
        // Create a unique ID if one doesn't exist
        let documentId = shipAssignment.id?.uuidString ?? UUID().uuidString
        
        // Prepare data
        var assignmentData: [String: Any] = [
            "userIdentifier": userIdentifier,
            "shipName": shipAssignment.shipName ?? "",
            "rank": shipAssignment.rank ?? "",
            "company": shipAssignment.company ?? "",
            "contractLength": shipAssignment.contractLength,
            "portOfJoining": shipAssignment.portOfJoining ?? "",
            "email": shipAssignment.email ?? "",
            "mobileNumber": shipAssignment.mobileNumber ?? "",
            "isPublic": shipAssignment.isPublic
        ]
        
        // Convert dates to timestamps
        if let dateOfOnboard = shipAssignment.dateOfOnboard {
            assignmentData["dateOfOnboard"] = Timestamp(date: dateOfOnboard)
        }
        
        // Save to Firestore
        db.collection("shipAssignments").document(documentId).setData(assignmentData) { error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            completion(.success(documentId))
        }
    }
    
    func fetchUserShipAssignments(userId: String, completion: @escaping (Result<[ShipAssignment], Error>) -> Void) {
        db.collection("shipAssignments")
            .whereField("userIdentifier", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                var assignments: [ShipAssignment] = []
                
                for document in documents {
                    let data = document.data()
                    
                    let assignment = ShipAssignment()
                    assignment.userIdentifier = data["userIdentifier"] as? String
                    assignment.shipName = data["shipName"] as? String
                    assignment.rank = data["rank"] as? String
                    assignment.company = data["company"] as? String
                    assignment.contractLength = data["contractLength"] as? Int ?? 6
                    assignment.portOfJoining = data["portOfJoining"] as? String
                    assignment.email = data["email"] as? String
                    assignment.mobileNumber = data["mobileNumber"] as? String
                    assignment.isPublic = data["isPublic"] as? Bool ?? false
                    
                    // Convert timestamp to Date
                    if let timestamp = data["dateOfOnboard"] as? Timestamp {
                        assignment.dateOfOnboard = timestamp.dateValue()
                    }
                    
                    assignments.append(assignment)
                }
                
                completion(.success(assignments))
            }
    }
    
    func fetchPublicShipAssignments(completion: @escaping (Result<[ShipAssignment], Error>) -> Void) {
        db.collection("shipAssignments")
            .whereField("isPublic", isEqualTo: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                var assignments: [ShipAssignment] = []
                
                for document in documents {
                    let data = document.data()
                    
                    let assignment = ShipAssignment()
                    assignment.userIdentifier = data["userIdentifier"] as? String
                    assignment.shipName = data["shipName"] as? String
                    assignment.rank = data["rank"] as? String
                    assignment.company = data["company"] as? String
                    assignment.contractLength = data["contractLength"] as? Int ?? 6
                    assignment.portOfJoining = data["portOfJoining"] as? String
                    assignment.email = data["email"] as? String
                    assignment.mobileNumber = data["mobileNumber"] as? String
                    assignment.isPublic = data["isPublic"] as? Bool ?? false
                    
                    // Convert timestamp to Date
                    if let timestamp = data["dateOfOnboard"] as? Timestamp {
                        assignment.dateOfOnboard = timestamp.dateValue()
                    }
                    
                    assignments.append(assignment)
                }
                
                completion(.success(assignments))
            }
    }
    
    // Enhanced function to search for compatible shipmates based on company, fleet, and time window
    func searchCompatibleShipmates(company: String, fleet: String, month: Int, completion: @escaping (Result<[ShipAssignment], Error>) -> Void) {
        // Calculate date range for a wider window (month ± 1)
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        
        // Start with the previous month
        var startDateComponents = DateComponents()
        startDateComponents.year = currentYear
        startDateComponents.month = max(1, month - 1)  // Don't go below January
        startDateComponents.day = 1
        
        // End with the next month
        var endDateComponents = DateComponents()
        endDateComponents.year = currentYear
        endDateComponents.month = min(12, month + 2)  // Don't go beyond December (+2 because we need the start of the month after)
        endDateComponents.day = 1
        
        guard let startDate = calendar.date(from: startDateComponents),
              let endMonthStart = calendar.date(from: endDateComponents) else {
            completion(.failure(NSError(domain: "FirebaseService", code: 100, userInfo: [NSLocalizedDescriptionKey: "Invalid date"])))
            return
        }
        
        // Get the end date (day before the start of the next month)
        let endDate = calendar.date(byAdding: .day, value: -1, to: endMonthStart) ?? endMonthStart
        
        // First, query for all ship assignments with matching company
        db.collection("shipAssignments")
            .whereField("isPublic", isEqualTo: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                let dispatchGroup = DispatchGroup()
                var matchedAssignments: [ShipAssignment] = []
                
                for document in documents {
                    let data = document.data()
                    let userIdentifier = data["userIdentifier"] as? String
                    let shipCompany = data["company"] as? String ?? ""
                    
                    // Skip documents not matching company criteria if company is specified
                    if !company.isEmpty && shipCompany.lowercased() != company.lowercased() {
                        continue
                    }
                    
                    // Skip if we don't have a user identifier
                    guard let uid = userIdentifier else { continue }
                    
                    dispatchGroup.enter()
                    
                    // Get the user profile to check fleet type
                    self.fetchUserProfileById(userId: uid) { userResult in
                        defer { dispatchGroup.leave() }
                        
                        switch userResult {
                        case .success(let userData):
                            // Case-insensitive fleet matching
                            let userFleet = (userData["fleetWorking"] as? String ?? "").lowercased()
                            
                            if fleet.lowercased().contains(userFleet) || userFleet.contains(fleet.lowercased()) {
                                // Check date criteria
                                if let onboardTimestamp = data["dateOfOnboard"] as? Timestamp {
                                    let onboardDate = onboardTimestamp.dateValue()
                                    
                                    // Create a ship assignment object
                                    let assignment = ShipAssignment()
                                    assignment.id = UUID()
                                    assignment.userIdentifier = userIdentifier
                                    assignment.shipName = data["shipName"] as? String
                                    assignment.rank = data["rank"] as? String
                                    assignment.company = data["company"] as? String
                                    assignment.contractLength = data["contractLength"] as? Int ?? 6
                                    assignment.portOfJoining = data["portOfJoining"] as? String
                                    assignment.email = data["email"] as? String
                                    assignment.mobileNumber = data["mobileNumber"] as? String
                                    assignment.isPublic = data["isPublic"] as? Bool ?? false
                                    assignment.dateOfOnboard = onboardDate
                                    
                                    // Calculate release date
                                    let releaseDate = assignment.expectedReleaseDate
                                    
                                    // Check if there's any overlap with our search window
                                    if (releaseDate >= startDate && releaseDate <= endDate) ||
                                       (onboardDate >= startDate && onboardDate <= endDate) {
                                        
                                        // Add user information to the assignment
                                        let user = User()
                                        user.userIdentifier = userIdentifier
                                        user.name = userData["name"] as? String
                                        user.surname = userData["surname"] as? String
                                        user.email = userData["email"] as? String
                                        user.fleetWorking = userData["fleetWorking"] as? String
                                        user.presentRank = userData["presentRank"] as? String
                                        user.company = userData["company"] as? String
                                        
                                        if let visibleString = userData["isProfileVisible"] as? Bool {
                                            user.isProfileVisible = visibleString
                                        }
                                        
                                        if let showEmailString = userData["showEmailToOthers"] as? Bool {
                                            user.showEmailToOthers = showEmailString
                                        }
                                        
                                        if let showPhoneString = userData["showPhoneToOthers"] as? Bool {
                                            user.showPhoneToOthers = showPhoneString
                                        }
                                        
                                        assignment.user = user
                                        matchedAssignments.append(assignment)
                                    }
                                }
                            }
                            
                        case .failure(_):
                            // Skip this user if we can't retrieve their profile
                            break
                        }
                    }
                }
                
                // When all async operations are complete, return the matches
                dispatchGroup.notify(queue: .main) {
                    completion(.success(matchedAssignments))
                }
            }
    }
    
    // Helper method to fetch a specific user's profile
    func fetchUserProfileById(userId: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard !userId.isEmpty else {
            completion(.failure(NSError(domain: "FirebaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty user ID"])))
            return
        }

        db.collection("users").document(userId).getDocument { document, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let document = document, document.exists, let data = document.data() else {
                completion(.failure(NSError(domain: "FirebaseService", code: 2, userInfo: [NSLocalizedDescriptionKey: "User profile not found"])))
                return
            }
            
            completion(.success(data))
        }
    }
    
    // MARK: - Land Assignments
    
    func saveLandAssignment(landAssignment: LandAssignment, completion: @escaping (Result<String, Error>) -> Void) {
        guard let userIdentifier = landAssignment.userIdentifier else {
            completion(.failure(NSError(domain: "FirebaseService", code: 3, userInfo: [NSLocalizedDescriptionKey: "User identifier missing"])))
            return
        }
        
        // Create a unique ID if one doesn't exist
        let documentId = landAssignment.id?.uuidString ?? UUID().uuidString
        
        // Prepare data
        var assignmentData: [String: Any] = [
            "userIdentifier": userIdentifier,
            "fleetType": landAssignment.fleetType ?? "",
            "lastVessel": landAssignment.lastVessel ?? "",
            "email": landAssignment.email ?? "",
            "mobileNumber": landAssignment.mobileNumber ?? "",
            "isPublic": landAssignment.isPublic
        ]
        
        // Convert dates to timestamps
        if let dateHome = landAssignment.dateHome {
            assignmentData["dateHome"] = Timestamp(date: dateHome)
        }
        
        if let expectedJoiningDate = landAssignment.expectedJoiningDate {
            assignmentData["expectedJoiningDate"] = Timestamp(date: expectedJoiningDate)
        }
        
        // Save to Firestore
        db.collection("landAssignments").document(documentId).setData(assignmentData) { error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            completion(.success(documentId))
        }
    }
    
    func fetchUserLandAssignments(userId: String, completion: @escaping (Result<[LandAssignment], Error>) -> Void) {
        db.collection("landAssignments")
            .whereField("userIdentifier", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                var assignments: [LandAssignment] = []
                
                for document in documents {
                    let data = document.data()
                    
                    let assignment = LandAssignment()
                    assignment.userIdentifier = data["userIdentifier"] as? String
                    assignment.fleetType = data["fleetType"] as? String
                    assignment.lastVessel = data["lastVessel"] as? String
                    assignment.email = data["email"] as? String
                    assignment.mobileNumber = data["mobileNumber"] as? String
                    assignment.isPublic = data["isPublic"] as? Bool ?? false
                    
                    // Convert timestamps to Dates
                    if let timestamp = data["dateHome"] as? Timestamp {
                        assignment.dateHome = timestamp.dateValue()
                    }
                    
                    if let timestamp = data["expectedJoiningDate"] as? Timestamp {
                        assignment.expectedJoiningDate = timestamp.dateValue()
                    }
                    
                    assignments.append(assignment)
                }
                
                completion(.success(assignments))
            }
    }
    
    func fetchPublicLandAssignments(completion: @escaping (Result<[LandAssignment], Error>) -> Void) {
        db.collection("landAssignments")
            .whereField("isPublic", isEqualTo: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                var assignments: [LandAssignment] = []
                
                for document in documents {
                    let data = document.data()
                    
                    let assignment = LandAssignment()
                    assignment.userIdentifier = data["userIdentifier"] as? String
                    assignment.fleetType = data["fleetType"] as? String
                    assignment.lastVessel = data["lastVessel"] as? String
                    assignment.email = data["email"] as? String
                    assignment.mobileNumber = data["mobileNumber"] as? String
                    assignment.isPublic = data["isPublic"] as? Bool ?? false
                    
                    // Convert timestamps to Dates
                    if let timestamp = data["dateHome"] as? Timestamp {
                        assignment.dateHome = timestamp.dateValue()
                    }
                    
                    if let timestamp = data["expectedJoiningDate"] as? Timestamp {
                        assignment.expectedJoiningDate = timestamp.dateValue()
                    }
                    
                    assignments.append(assignment)
                }
                
                completion(.success(assignments))
            }
    }
    
    // MARK: - User Search
    
    func searchUsersByEmail(email: String, completion: @escaping (Result<[User], Error>) -> Void) {
        db.collection("users")
            .whereField("email", isEqualTo: email)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                var users: [User] = []
                
                for document in documents {
                    let data = document.data()
                    
                    let user = User()
                    user.userIdentifier = document.documentID
                    user.name = data["name"] as? String
                    user.surname = data["surname"] as? String
                    user.email = data["email"] as? String
                    user.mobileNumber = data["mobileNumber"] as? String
                    user.fleetWorking = data["fleetWorking"] as? String
                    user.presentRank = data["presentRank"] as? String
                    
                    if let statusString = data["currentStatus"] as? String,
                       let status = UserStatus(rawValue: statusString) {
                        user.currentStatus = status
                    }
                    
                    users.append(user)
                }
                
                completion(.success(users))
            }
    }
    
    // MARK: - Data Synchronization
    
    func forceSync() {
        // Check if we're signed in
        guard let userId = getCurrentUserId() else {
            print("Cannot sync: No user signed in")
            return
        }
        
        // Sync user profile - using "users" document ID
        fetchUserProfile { result in
            switch result {
            case .success(let userData):
                print("Successfully fetched user profile from Firebase")
                // Data is processed in the UI layer now
            case .failure(let error):
                print("Error syncing user profile: \(error.localizedDescription)")
            }
        }
        
        // Sync ship assignments
        db.collection("shipAssignments")
            .whereField("userIdentifier", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error syncing ship assignments: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("No ship assignments found")
                    return
                }
                
                print("Found \(documents.count) ship assignments")
                // Data is processed in the UI layer
            }
        
        // Sync land assignments
        db.collection("landAssignments")
            .whereField("userIdentifier", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error syncing land assignments: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("No land assignments found")
                    return
                }
                
                print("Found \(documents.count) land assignments")
                // Data is processed in the UI layer
            }
    }
    
    // Delete a ship assignment from Firestore
    func deleteShipAssignment(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        db.collection("shipAssignments").document(id).delete { error in
            if let error = error {
                completion(.failure(error))
                return
            }
            completion(.success(()))
        }
    }
    
    // Delete a land assignment from Firestore
    func deleteLandAssignment(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        db.collection("landAssignments").document(id).delete { error in
            if let error = error {
                completion(.failure(error))
                return
            }
            completion(.success(()))
        }
    }
} 
