//
//  FirebaseService.swift
//  Fleet Manager
//
//  Created by Deepak Kumar on 31/03/2025.
//

import Foundation
import Firebase
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import SwiftData
import UIKit

/// Service class for handling Firebase operations
class FirebaseService {
    static let shared = FirebaseService()
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    private init() {
        // Configure Firestore settings
        let settings = FirestoreSettings()
        // Don't enable persistence for offline caching
        settings.cacheSettings = PersistentCacheSettings()
        db.settings = settings
    }
    
    // MARK: - Photo Upload
    
    func uploadUserPhoto(userId: String, image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        // Convert image to data
        guard let imageData = image.jpegData(compressionQuality: 0.5) else {
            completion(.failure(NSError(domain: "FirebaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"])))
            return
        }
        
        // Create a reference to the file with a proper path
        let photoRef = storage.reference().child("users/\(userId)/profile.jpg")
        
        // Upload the file
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        // Upload the photo
        photoRef.putData(imageData, metadata: metadata) { metadata, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            // Get the download URL
            photoRef.downloadURL { url, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let downloadURL = url else {
                    completion(.failure(NSError(domain: "FirebaseService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL"])))
                    return
                }
                
                // Update user profile with photo URL
                self.db.collection("users").document(userId).updateData([
                    "photoURL": downloadURL.absoluteString
                ]) { error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }
                    
                    completion(.success(downloadURL.absoluteString))
                }
            }
        }
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
    
    func saveUserProfile(user: User, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let userId = user.userIdentifier else {
            completion(.failure(NSError(domain: "FirebaseService", code: 3, userInfo: [NSLocalizedDescriptionKey: "User identifier missing"])))
            return
        }
        
        // Prepare user data
        var userData: [String: Any] = [
            "name": user.name ?? "",
            "surname": user.surname ?? "",
            "email": user.email ?? "",
            "mobileNumber": user.mobileNumber ?? "",
            "company": user.company ?? "",
            "fleetWorking": user.fleetWorking ?? "",
            "presentRank": user.presentRank ?? "",
            "currentStatus": user.currentStatus.rawValue,
            "showEmailToOthers": user.showEmailToOthers,
            "showPhoneToOthers": user.showPhoneToOthers,
            "photoURL": user.photoURL ?? ""
        ]
        
        // First check if the document already exists
        let userRef = db.collection("users").document(userId)
        userRef.getDocument { [weak self] document, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Error checking if user exists: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            let saveOperation: (Error?) -> Void = { error in
                if let error = error {
                    print("❌ Error saving user profile: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                // Update fleet information in all of the user's assignments
                self.updateUserAssignmentsWithLatestFleet(userId: userId, fleetType: user.fleetWorking ?? "")
                
                print("✅ User profile saved successfully")
                completion(.success(true))
            }
            
            if let document = document, document.exists {
                // User exists, update the document
                print("👤 Updating existing user document for \(userId)")
                userRef.updateData(userData, completion: saveOperation)
            } else {
                // User doesn't exist, create a new document
                print("✨ Creating new user document for \(userId)")
                userRef.setData(userData, completion: saveOperation)
            }
        }
    }
    
    // New function to update assignments with the latest fleet information
    private func updateUserAssignmentsWithLatestFleet(userId: String, fleetType: String) {
        // Update ship assignments
        let shipQuery = db.collection("shipAssignments").whereField("userIdentifier", isEqualTo: userId)
        shipQuery.getDocuments { [weak self] snapshot, error in
            guard let self = self, let documents = snapshot?.documents else { return }
            
            let batch = self.db.batch()
            for document in documents {
                batch.updateData(["fleetType": fleetType], forDocument: document.reference)
            }
            
            // Commit the batch
            if !documents.isEmpty {
                batch.commit()
            }
        }
        
        // Update land assignments
        let landQuery = db.collection("landAssignments").whereField("userIdentifier", isEqualTo: userId)
        landQuery.getDocuments { [weak self] snapshot, error in
            guard let self = self, let documents = snapshot?.documents else { return }
            
            let batch = self.db.batch()
            for document in documents {
                batch.updateData(["fleetType": fleetType], forDocument: document.reference)
            }
            
            // Commit the batch
            if !documents.isEmpty {
                batch.commit()
            }
        }
    }
    
    // Helper function to update ship assignments when user profile changes
    private func updateShipAssignmentsForUser(userId: String, userData: User, completion: @escaping (Result<Void, Error>) -> Void) {
        // Get all ship assignments for this user
        db.collection("shipAssignments")
            .whereField("userIdentifier", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    // No ship assignments found - this is not an error
                    completion(.success(()))
                    return
                }
                
                let dispatchGroup = DispatchGroup()
                var updateError: Error?
                
                // Update each assignment with new user data
                for document in documents {
                    dispatchGroup.enter()
                    
                    // Fields to sync between user and ship assignment
                    var updateData: [String: Any] = [:]
                    
                    // Only update if user has chosen to share this info
                    if userData.showEmailToOthers, let email = userData.email {
                        updateData["email"] = email
                    }
                    
                    if userData.showPhoneToOthers, let phone = userData.mobileNumber {
                        updateData["mobileNumber"] = phone
                    }
                    
                    // Always update these fields
                    if let rank = userData.presentRank {
                        updateData["rank"] = rank
                    }
                    
                    if let company = userData.company {
                        updateData["company"] = company
                    }
                    
                    // Also update fleet type to keep synchronized
                    if let fleetWorking = userData.fleetWorking {
                        updateData["fleetType"] = fleetWorking
                    }
                    
                    // Update the document if there's anything to update
                    if !updateData.isEmpty {
                        self.db.collection("shipAssignments").document(document.documentID).updateData(updateData) { error in
                            if let error = error {
                                updateError = error
                            }
                            dispatchGroup.leave()
                        }
                    } else {
                        dispatchGroup.leave()
                    }
                }
                
                dispatchGroup.notify(queue: .main) {
                    if let error = updateError {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                }
            }
    }
    
    // Helper function to update land assignments when user profile changes
    private func updateLandAssignmentsForUser(userId: String, userData: User, completion: @escaping (Result<Void, Error>) -> Void) {
        // Get all land assignments for this user
        db.collection("landAssignments")
            .whereField("userIdentifier", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    // No land assignments found - this is not an error
                    completion(.success(()))
                    return
                }
                
                let dispatchGroup = DispatchGroup()
                var updateError: Error?
                
                // Update each assignment with new user data
                for document in documents {
                    dispatchGroup.enter()
                    
                    // Fields to sync between user and land assignment
                    var updateData: [String: Any] = [:]
                    
                    // Only update if user has chosen to share this info
                    if userData.showEmailToOthers, let email = userData.email {
                        updateData["email"] = email
                    }
                    
                    if userData.showPhoneToOthers, let phone = userData.mobileNumber {
                        updateData["mobileNumber"] = phone
                    }
                    
                    // Always update company and fleet type
                    if let company = userData.company {
                        updateData["company"] = company
                    }
                    
                    if let fleetWorking = userData.fleetWorking {
                        updateData["fleetType"] = fleetWorking
                    }
                    
                    // Update the document if there's anything to update
                    if !updateData.isEmpty {
                        self.db.collection("landAssignments").document(document.documentID).updateData(updateData) { error in
                            if let error = error {
                                updateError = error
                            }
                            dispatchGroup.leave()
                        }
                    } else {
                        dispatchGroup.leave()
                    }
                }
                
                dispatchGroup.notify(queue: .main) {
                    if let error = updateError {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                }
            }
    }
    
    func updateUserStatus(isOnShip: Bool, user: User? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = getCurrentUserId() else {
            completion(.failure(NSError(domain: "FirebaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])))
            return
        }
        
        // Update only the status field in the user document
        let newStatus = isOnShip ? UserStatus.onShip.rawValue : UserStatus.onLand.rawValue
        
        var updateData: [String: Any] = ["currentStatus": newStatus]
        
        // If user is provided and we're updating to onLand status, also update company
        if !isOnShip, let user = user {
            updateData["company"] = user.company ?? AppConstants.defaultCompany
        }
        
        db.collection("users").document(userId).updateData(updateData) { error in
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
        
        // First fetch the latest user profile to ensure we have the most up-to-date information
        fetchUserProfileById(userId: userIdentifier) { result in
            switch result {
            case .success(let userData):
                // Use the user's ID as the document ID
                let documentId = userIdentifier
                
                // Prepare data with the latest user information
        var assignmentData: [String: Any] = [
            "userIdentifier": userIdentifier,
            "shipName": shipAssignment.shipName ?? "",
                    "rank": shipAssignment.rank ?? userData["presentRank"] as? String ?? "",
                    "company": shipAssignment.company ?? userData["company"] as? String ?? "",
            "contractLength": shipAssignment.contractLength,
            "portOfJoining": shipAssignment.portOfJoining ?? "",
                    "isPublic": shipAssignment.isPublic,
                    // Always use the latest fleet type from user profile
                    "fleetType": userData["fleetWorking"] as? String ?? shipAssignment.fleetType ?? ""
                ]
                
                // Add contact information based on user's privacy settings
                if let showEmail = userData["showEmailToOthers"] as? Bool, showEmail,
                   let email = userData["email"] as? String {
                    assignmentData["email"] = email
                } else {
                    assignmentData["email"] = shipAssignment.email ?? ""
                }
                
                if let showPhone = userData["showPhoneToOthers"] as? Bool, showPhone,
                   let phone = userData["mobileNumber"] as? String {
                    assignmentData["mobileNumber"] = phone
                } else {
                    assignmentData["mobileNumber"] = shipAssignment.mobileNumber ?? ""
                }
        
        // Convert dates to timestamps
        if let dateOfOnboard = shipAssignment.dateOfOnboard {
            assignmentData["dateOfOnboard"] = Timestamp(date: dateOfOnboard)
        }
        
                // Check if document exists first
                let docRef = self.db.collection("shipAssignments").document(documentId)
                docRef.getDocument { document, error in
                    if let error = error {
                        print("❌ Error checking if ship assignment exists: \(error.localizedDescription)")
                        completion(.failure(error))
                        return
                    }
                    
                    let saveOperation = { 
        // Save to Firestore
                        docRef.setData(assignmentData) { error in
            if let error = error {
                                print("❌ Error saving ship assignment: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
                            print("✅ Ship assignment saved successfully")
            completion(.success(documentId))
                        }
                    }
                    
                    if let document = document, document.exists {
                        print("🚢 Updating existing ship assignment for user \(userIdentifier)")
                        // Delete other assignments first to avoid duplicates
                        self.deleteAllUserAssignments(userId: userIdentifier, collectionName: "shipAssignments", keepOne: false) { result in
                            // Whether deletion succeeded or failed, still save the current assignment
                            saveOperation()
                        }
                    } else {
                        print("✨ Creating new ship assignment for user \(userIdentifier)")
                        saveOperation()
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
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
    func searchCompatibleShipmates(company: String, fleet: String, month: Int, exactDate: Date? = nil, completion: @escaping (Result<[ShipAssignment], Error>) -> Void) {
        print("\n🔍 STARTING SHIP SEARCH with criteria - Company: '\(company)', Fleet: '\(fleet)', Month: \(month)")
        
        // First check if the current user has a ship assignment to calculate release date
        guard let userId = getCurrentUserId() else {
            completion(.failure(NSError(domain: "FirebaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])))
            return
        }
        
        // If an exact date is provided (from a land assignment's expected joining date), 
        // use that directly with a tighter window
        if let exactDate = exactDate {
            print("📅 Using exact date for search: \(exactDate.formatted(date: .complete, time: .omitted))")
            performShipSearchWithExactDate(company: company, fleet: fleet, targetDate: exactDate, completion: completion)
            return
        }
        
        // Otherwise use the month-based search (for ship assignments)
        // Determine the search month - either from user's contract or use passed month
        var searchMonth = month
        var releaseDate: Date?
        
        // Try to find the current user's ship assignment and use its expected release date
        db.collection("shipAssignments")
            .whereField("userIdentifier", isEqualTo: userId)
            .getDocuments { snapshot, error in
                // If we can't find the user's assignment, proceed with the default month
                if let error = error {
                    print("⚠️ Error getting user's ship assignment: \(error.localizedDescription). Using default month \(month).")
                } else if let documents = snapshot?.documents, let doc = documents.first {
                    // User has a ship assignment, calculate release date
                    let data = doc.data()
                    
                    if let onboardTimestamp = data["dateOfOnboard"] as? Timestamp,
                       let contractLength = data["contractLength"] as? Int {
                        let onboardDate = onboardTimestamp.dateValue()
                        
                        // Calculate expected release date
        let calendar = Calendar.current
                        if let calculatedReleaseDate = calendar.date(byAdding: .month, value: contractLength, to: onboardDate) {
                            releaseDate = calculatedReleaseDate
                            searchMonth = calendar.component(.month, from: calculatedReleaseDate)
                            print("📊 Using calculated release month: \(searchMonth) from contract")
                        }
                    }
                }
                
                // Continue with the search using either the default or calculated month
                self.performShipSearch(company: company, fleet: fleet, month: searchMonth, completion: completion)
            }
    }
    
    // New function to search with an exact date and tighter window (±15 days)
    private func performShipSearchWithExactDate(company: String, fleet: String, targetDate: Date, completion: @escaping (Result<[ShipAssignment], Error>) -> Void) {
        // Calculate date range for a tight window (targetDate ± 15 days)
        let calendar = Calendar.current
        
        // 15 days before target date
        guard let startDate = calendar.date(byAdding: .day, value: -15, to: targetDate) else {
            completion(.failure(NSError(domain: "FirebaseService", code: 100, userInfo: [NSLocalizedDescriptionKey: "Invalid date calculation"])))
            return
        }
        
        // 15 days after target date
        guard let endDate = calendar.date(byAdding: .day, value: 15, to: targetDate) else {
            completion(.failure(NSError(domain: "FirebaseService", code: 100, userInfo: [NSLocalizedDescriptionKey: "Invalid date calculation"])))
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        print("📅 Using TIGHT date window (±15 days): \(dateFormatter.string(from: startDate)) to \(dateFormatter.string(from: endDate))")
        
        // Query for all ship assignments with matching company
        print("📡 Querying Firestore for public ship assignments")
        db.collection("shipAssignments")
            .whereField("isPublic", isEqualTo: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ ERROR fetching ship assignments: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("📊 No public ship assignments found")
                    completion(.success([]))
                    return
                }
                
                // Process matches
                let dispatchGroup = DispatchGroup()
                var matchedAssignments: [ShipAssignment] = []
                var successfulMatches = 0
                
                print("📊 Found \(documents.count) public ship assignments. Processing...")
                
                // Process each assignment
                for document in documents {
                    let data = document.data()
                    
                    guard let userIdentifier = data["userIdentifier"] as? String else {
                        continue
                    }
                    
                    let companyFromData = (data["company"] as? String ?? "").lowercased()
                    
                    // More flexible company matching - either exact match or contains
                    let companyMatch = company.lowercased() == companyFromData || 
                                      company.lowercased().contains(companyFromData) ||
                                      companyFromData.contains(company.lowercased())
                    
                    if companyMatch {
                    dispatchGroup.enter()
                    
                        // Fetch user details to check fleet compatibility
                        self.fetchUserProfileById(userId: userIdentifier) { userResult in
                        defer { dispatchGroup.leave() }
                        
                        switch userResult {
                        case .success(let userData):
                                // Get fleet type from user data
                            let userFleet = (userData["fleetWorking"] as? String ?? "").lowercased()
                                let fleetMatch = fleet.lowercased().contains(userFleet) || userFleet.contains(fleet.lowercased())
                                
                                print("👤 Ship user: \(userData["name"] as? String ?? "") - Fleet: '\(userFleet)', Company: '\(companyFromData)'")
                                print("🔍 Company match: \(companyMatch ? "✅" : "❌") - Fleet match: \(fleetMatch ? "✅" : "❌")")
                                
                                // Check if there's a company/fleet match
                                if companyMatch && fleetMatch {
                                if let onboardTimestamp = data["dateOfOnboard"] as? Timestamp {
                                    let onboardDate = onboardTimestamp.dateValue()
                                        
                                        print("📅 Assignment onboard date: \(dateFormatter.string(from: onboardDate))")
                                    
                                    // Create a ship assignment object
                                    let assignment = ShipAssignment()
                                    assignment.id = UUID()
                                    assignment.userIdentifier = userIdentifier
                                    assignment.shipName = data["shipName"] as? String
                                        assignment.rank = data["rank"] as? String ?? ""
                                    assignment.company = data["company"] as? String
                                    assignment.contractLength = data["contractLength"] as? Int ?? 6
                                    assignment.portOfJoining = data["portOfJoining"] as? String
                                    assignment.email = data["email"] as? String
                                    assignment.mobileNumber = data["mobileNumber"] as? String
                                    assignment.isPublic = data["isPublic"] as? Bool ?? false
                                    assignment.dateOfOnboard = onboardDate
                                    
                                    // Calculate release date
                                    let releaseDate = assignment.expectedReleaseDate
                                    
                                        print("📅 Expected release date: \(dateFormatter.string(from: releaseDate!))")
                                        
                                        // Strict check with our tight window - only release date matters
                                        let releaseDateInWindow = releaseDate! >= startDate && releaseDate! <= endDate
                                        
                                        if releaseDateInWindow {
                                            print("✅ Date MATCH - Release date is within tight search window")
                                        
                                        // Add user information to the assignment
                                        let user = User()
                                        user.userIdentifier = userIdentifier
                                        user.name = userData["name"] as? String
                                        user.surname = userData["surname"] as? String
                                        user.email = userData["email"] as? String
                                        user.fleetWorking = userData["fleetWorking"] as? String
                                        user.presentRank = userData["presentRank"] as? String
                                            user.company = userData["company"] as? String ?? AppConstants.defaultCompany
                                        
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
                                            successfulMatches += 1
                                            print("🎯 MATCH FOUND: User \(user.name ?? "") \(user.surname ?? "") with rank \(user.presentRank ?? "Unknown")")
                                        } else {
                                            print("❌ Date MISMATCH - Release date outside tight search window")
                                        }
                                    }
                                }
                                
                            case .failure(let error):
                                print("❌ ERROR fetching user profile: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                
                dispatchGroup.notify(queue: .main) {
                    print("📊 Processed all ship assignments. Found \(successfulMatches) matches.")
                    completion(.success(matchedAssignments))
                }
            }
    }
    
    private func performShipSearch(company: String, fleet: String, month: Int, completion: @escaping (Result<[ShipAssignment], Error>) -> Void) {
        // Calculate date range for a wider window (month ± 2)
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        
        // Start with two months before
        var startDateComponents = DateComponents()
        startDateComponents.year = currentYear
        startDateComponents.month = max(1, month - 2)  // Don't go below January
        startDateComponents.day = 1
        
        // End two months after
        var endDateComponents = DateComponents()
        endDateComponents.year = currentYear
        endDateComponents.month = min(12, month + 3)  // Don't go beyond December (+3 because we need the start of the month after)
        endDateComponents.day = 1
        
        guard let startDate = calendar.date(from: startDateComponents),
              let endMonthStart = calendar.date(from: endDateComponents) else {
            print("❌ ERROR: Invalid date calculation in searchCompatibleShipmates")
            completion(.failure(NSError(domain: "FirebaseService", code: 100, userInfo: [NSLocalizedDescriptionKey: "Invalid date"])))
            return
        }

        // Get the end date (day before the start of the next month)
        let endDate = calendar.date(byAdding: .day, value: -1, to: endMonthStart) ?? endMonthStart
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        print("📅 Using WIDER date window: \(dateFormatter.string(from: startDate)) to \(dateFormatter.string(from: endDate)) (target month: \(month))")
        
        // First, query for all ship assignments with matching company
        print("📡 Querying Firestore for public ship assignments")
        
        // Default company if empty
        let searchCompany = company.isEmpty ? AppConstants.defaultCompany.lowercased() : company.lowercased()
        
        db.collection("shipAssignments")
            .whereField("isPublic", isEqualTo: true)
            .getDocuments { snapshot, error in
            if let error = error {
                    print("❌ ERROR querying ship assignments: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
                guard let documents = snapshot?.documents else {
                    print("ℹ️ No public ship assignments found")
                    completion(.success([]))
                return
            }
            
                print("📊 Found \(documents.count) public ship assignments. Processing...")
                
                var matchedAssignments: [ShipAssignment] = []
                let dispatchGroup = DispatchGroup()
                var successfulMatches = 0
                
                // Process each ship assignment
                for document in documents {
                    let data = document.data()
                    
                    // Extract user identifier
                    guard let userIdentifier = data["userIdentifier"] as? String else { continue }
                    
                    // Skip if this is the current user's assignment
                    if userIdentifier == self.getCurrentUserId() { continue }
                    
                    // Check date window compatibility
                    var onboardDateInWindow = false
                    
                    if let onboardTimestamp = data["dateOfOnboard"] as? Timestamp {
                        let onboardDate = onboardTimestamp.dateValue()
                        
                        // Get contractLength
                        let contractLength = data["contractLength"] as? Int ?? 6
                        
                        // Calculate expected release date
                        if let releaseDate = calendar.date(byAdding: .month, value: contractLength, to: onboardDate) {
                            
                            // If onboard date is before our window start, check release date
                            if onboardDate <= startDate {
                                // Check if release date is after our window start (i.e., ends during our window)
                                onboardDateInWindow = releaseDate >= startDate
                                
                                if onboardDateInWindow {
                                    print("📅 Ship ends during our window - Onboard: \(onboardDate.formatted(date: .long, time: .omitted)), Release: \(releaseDate.formatted(date: .long, time: .omitted))")
                                }
                            } 
                            // If onboard date is within our window
                            else if onboardDate <= endDate {
                                onboardDateInWindow = true
                                print("📅 Ship starts during our window - Onboard: \(onboardDate.formatted(date: .long, time: .omitted)), Release: \(releaseDate.formatted(date: .long, time: .omitted))")
                            }
                        }
                    }
                    
                    if onboardDateInWindow {
                        dispatchGroup.enter()
                        
                        self.fetchUserProfileById(userId: userIdentifier) { userResult in
                            defer { dispatchGroup.leave() }
                            
                            switch userResult {
                            case .success(let userData):
                                // Get fleet type from user data
                                let userFleet = (userData["fleetWorking"] as? String ?? "").lowercased()
                                let fleetMatch = fleet.isEmpty || fleet.lowercased().contains(userFleet) || userFleet.contains(fleet.lowercased())
                                
                                // Get company data
                                let companyFromAssignment = (data["company"] as? String ?? "").lowercased()
                                let companyFromData = (userData["company"] as? String ?? companyFromAssignment).lowercased()
                                
                                // More flexible company matching
                                let companyMatch = searchCompany.isEmpty || 
                                                searchCompany == companyFromData || 
                                                searchCompany.contains(companyFromData) || 
                                                companyFromData.contains(searchCompany)
                                
                                print("👤 Ship user: \(userData["name"] as? String ?? "") - Fleet: '\(userFleet)', Company: '\(companyFromData)'")
                                print("🔍 Company match: \(companyMatch ? "✅" : "❌") - Fleet match: \(fleetMatch ? "✅" : "❌")")
                                
                                // Check if there's a company/fleet match
                                if companyMatch && fleetMatch {
                                    print("✅ Company/Fleet MATCH - \(searchCompany) / \(fleet.lowercased())")
                                    
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
                                    
                                    // Convert timestamp to Date
                                    if let timestamp = data["dateOfOnboard"] as? Timestamp {
                                        assignment.dateOfOnboard = timestamp.dateValue()
                                    }
                                    
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
                                    successfulMatches += 1
                                    print("🎯 MATCH FOUND: User \(user.name ?? "") \(user.surname ?? "") with rank \(user.presentRank ?? "Unknown")")
                                }
                                
                            case .failure(let error):
                                print("❌ ERROR fetching user profile: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                
                dispatchGroup.notify(queue: .main) {
                    print("📊 Processed all ship assignments. Found \(successfulMatches) matches.")
                    completion(.success(matchedAssignments))
                }
        }
    }
    
    // MARK: - Land Assignments
    
    func saveLandAssignment(landAssignment: LandAssignment, completion: @escaping (Result<String, Error>) -> Void) {
        guard let userIdentifier = landAssignment.userIdentifier else {
            completion(.failure(NSError(domain: "FirebaseService", code: 3, userInfo: [NSLocalizedDescriptionKey: "User identifier missing"])))
            return
        }
        
        // First fetch the latest user profile to ensure we have the most up-to-date information
        fetchUserProfileById(userId: userIdentifier) { result in
            switch result {
            case .success(let userData):
                // Use the user's ID as the document ID
                let documentId = userIdentifier
                
                // Prepare data with the latest user information
        var assignmentData: [String: Any] = [
            "userIdentifier": userIdentifier,
                    "company": landAssignment.company ?? userData["company"] as? String ?? "",
                    "fleetType": userData["fleetWorking"] as? String ?? landAssignment.fleetType ?? "",
            "lastVessel": landAssignment.lastVessel ?? "",
            "isPublic": landAssignment.isPublic
        ]
                
                // Add contact information based on user's privacy settings
                if let showEmail = userData["showEmailToOthers"] as? Bool, showEmail,
                   let email = userData["email"] as? String {
                    assignmentData["email"] = email
                } else {
                    assignmentData["email"] = landAssignment.email ?? ""
                }
                
                if let showPhone = userData["showPhoneToOthers"] as? Bool, showPhone,
                   let phone = userData["mobileNumber"] as? String {
                    assignmentData["mobileNumber"] = phone
                } else {
                    assignmentData["mobileNumber"] = landAssignment.mobileNumber ?? ""
                }
        
        // Convert dates to timestamps
        if let dateHome = landAssignment.dateHome {
            assignmentData["dateHome"] = Timestamp(date: dateHome)
        }
        
        if let expectedJoiningDate = landAssignment.expectedJoiningDate {
            assignmentData["expectedJoiningDate"] = Timestamp(date: expectedJoiningDate)
        }
        
                // Check if document exists first
                let docRef = self.db.collection("landAssignments").document(documentId)
                docRef.getDocument { document, error in
                    if let error = error {
                        print("❌ Error checking if land assignment exists: \(error.localizedDescription)")
                        completion(.failure(error))
                        return
                    }
                    
                    let saveOperation = { 
        // Save to Firestore
                        docRef.setData(assignmentData) { error in
            if let error = error {
                                print("❌ Error saving land assignment: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
                            print("✅ Land assignment saved successfully")
            completion(.success(documentId))
                        }
                    }
                    
                    if let document = document, document.exists {
                        print("🏠 Updating existing land assignment for user \(userIdentifier)")
                        // Delete other assignments first to avoid duplicates
                        self.deleteAllUserAssignments(userId: userIdentifier, collectionName: "landAssignments", keepOne: false) { result in
                            // Whether deletion succeeded or failed, still save the current assignment
                            saveOperation()
                        }
                    } else {
                        print("✨ Creating new land assignment for user \(userIdentifier)")
                        saveOperation()
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
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
                    assignment.company = data["company"] as? String ?? AppConstants.defaultCompany
                    
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
                    assignment.company = data["company"] as? String ?? AppConstants.defaultCompany
                    
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
    
    // Enhanced function to search for compatible land assignments for someone on a ship
    func searchCompatibleLandAssignments(company: String, fleet: String, month: Int, exactDate: Date? = nil, completion: @escaping (Result<[LandAssignment], Error>) -> Void) {
        print("\n🔍 STARTING LAND SEARCH with criteria - Company: '\(company)', Fleet: '\(fleet)', Month: \(month)")
        
        // First check if the current user has a ship assignment to calculate release date
        guard let userId = getCurrentUserId() else {
            completion(.failure(NSError(domain: "FirebaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])))
            return
        }
        
        // If an exact date is provided (for tight window search), use it directly
        if let exactDate = exactDate {
            print("📅 Using exact date for search: \(exactDate.formatted(date: .complete, time: .omitted))")
            performLandSearchWithExactDate(company: company, fleet: fleet, targetDate: exactDate, completion: completion)
            return
        }
        
        // Determine the search month - either from user's contract or use passed month
        var searchMonth = month
        var releaseDate: Date?
        
        // Try to find the current user's ship assignment and use its expected release date
        db.collection("shipAssignments")
            .whereField("userIdentifier", isEqualTo: userId)
            .getDocuments { snapshot, error in
                // If we can't find the user's assignment, proceed with the default month
                if let error = error {
                    print("⚠️ Error getting user's ship assignment: \(error.localizedDescription). Using default month \(month).")
                } else if let documents = snapshot?.documents, let doc = documents.first {
                    // User has a ship assignment, calculate release date
                    let data = doc.data()
                    
                    if let onboardTimestamp = data["dateOfOnboard"] as? Timestamp,
                       let contractLength = data["contractLength"] as? Int {
                        let onboardDate = onboardTimestamp.dateValue()
                        
                        // Calculate expected release date
                        let calendar = Calendar.current
                        if let calculatedReleaseDate = calendar.date(byAdding: .month, value: contractLength, to: onboardDate) {
                            releaseDate = calculatedReleaseDate
                            searchMonth = calendar.component(.month, from: calculatedReleaseDate)
                            print("📊 Using calculated release month: \(searchMonth) from contract")
                        }
                    }
                }
                
                // Continue with the search using either the default or calculated month
                self.performLandSearch(company: company, fleet: fleet, month: searchMonth, completion: completion)
            }
    }
    
    // New function to perform land search with an exact date and tighter window (±15 days)
    private func performLandSearchWithExactDate(company: String, fleet: String, targetDate: Date, completion: @escaping (Result<[LandAssignment], Error>) -> Void) {
        // Calculate date range for a tight window (targetDate ± 15 days)
        let calendar = Calendar.current
        
        // 15 days before target date
        guard let startDate = calendar.date(byAdding: .day, value: -15, to: targetDate) else {
            completion(.failure(NSError(domain: "FirebaseService", code: 100, userInfo: [NSLocalizedDescriptionKey: "Invalid date calculation"])))
            return
        }
        
        // 15 days after target date
        guard let endDate = calendar.date(byAdding: .day, value: 15, to: targetDate) else {
            completion(.failure(NSError(domain: "FirebaseService", code: 100, userInfo: [NSLocalizedDescriptionKey: "Invalid date calculation"])))
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        print("📅 Using TIGHT date window (±15 days): \(dateFormatter.string(from: startDate)) to \(dateFormatter.string(from: endDate))")
        
        // Query for all land assignments with matching company
        print("📡 Querying Firestore for public land assignments")
        
        db.collection("landAssignments")
            .whereField("isPublic", isEqualTo: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ ERROR querying land assignments: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("ℹ️ No public land assignments found")
                    completion(.success([]))
                    return
                }
                
                print("📊 Found \(documents.count) public land assignments. Processing...")
                
                var matchedAssignments: [LandAssignment] = []
                let dispatchGroup = DispatchGroup()
                var successfulMatches = 0
                
                // Process each land assignment
                for document in documents {
                    let data = document.data()
                    
                    // Extract user identifier
                    guard let uid = data["userIdentifier"] as? String else { continue }
                    
                    // Skip if this is the current user's assignment
                    if uid == self.getCurrentUserId() { continue }
                    
                    // Check if the expected joining date is within our window
                    var dateMatch = false
                    if let expectedJoiningTimestamp = data["expectedJoiningDate"] as? Timestamp {
                        let joiningDate = expectedJoiningTimestamp.dateValue()
                        
                        // Check if the joiningDate is within our window
                        dateMatch = (joiningDate >= startDate && joiningDate <= endDate)
                        
                        print("📅 Expected joining date: \(joiningDate.formatted(date: .long, time: .omitted)) - \(dateMatch ? "✅ within window" : "❌ outside window")")
                    }
                    
                    if dateMatch {
                        dispatchGroup.enter()
                        
                        self.fetchUserProfileById(userId: uid) { userResult in
                            defer { dispatchGroup.leave() }
                            
                            switch userResult {
                            case .success(let userData):
                                // Fleet from land assignment
                                let landFleet = (data["fleetType"] as? String ?? "").lowercased()
                                let userRank = userData["presentRank"] as? String ?? ""
                                
                                print("👤 User \(uid) - Fleet: '\(landFleet)', Rank: '\(userRank)'")
                                
                                // Fleet compatibility check
                                let fleetMatch = fleet.isEmpty || fleet.lowercased().contains(landFleet) || landFleet.contains(fleet.lowercased())
                                
                                // Company compatibility check - if company is empty, use default company
                                let searchCompany = company.isEmpty ? AppConstants.defaultCompany.lowercased() : company.lowercased()
                                let userCompany = (userData["company"] as? String ?? AppConstants.defaultCompany).lowercased()
                                let landCompany = (data["company"] as? String ?? userCompany).lowercased()
                                
                                // More flexible company matching - either exact match or contains
                                let companyMatch = searchCompany == landCompany || 
                                                  searchCompany.contains(landCompany) ||
                                                  landCompany.contains(searchCompany)
                                
                                print("🔍 Company match: \(companyMatch ? "✅" : "❌") - Fleet match: \(fleetMatch ? "✅" : "❌")")
                                
                                if companyMatch && fleetMatch {
                                    print("✅ Company/Fleet MATCH - \(searchCompany) / \(fleet.lowercased())")
                                    
                                    let assignment = LandAssignment()
                                    assignment.id = UUID()
                                    assignment.userIdentifier = uid
                                    assignment.fleetType = data["fleetType"] as? String
                                    assignment.lastVessel = data["lastVessel"] as? String
                                    assignment.email = data["email"] as? String
                                    assignment.mobileNumber = data["mobileNumber"] as? String
                                    assignment.isPublic = data["isPublic"] as? Bool ?? false
                                    assignment.company = data["company"] as? String
                                    
                                    // Convert timestamps to dates
                                    if let timestamp = data["dateHome"] as? Timestamp {
                                        assignment.dateHome = timestamp.dateValue()
                                    }
                                    
                                    if let timestamp = data["expectedJoiningDate"] as? Timestamp {
                                        assignment.expectedJoiningDate = timestamp.dateValue()
                                    }
                                    
                                    // Add user information to the assignment
                                    let user = User()
                                    user.userIdentifier = uid
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
                                    successfulMatches += 1
                                    print("🎯 MATCH FOUND: User \(user.name ?? "") \(user.surname ?? "") with rank \(user.presentRank ?? "Unknown")")
                                }
                                
                            case .failure(let error):
                                print("❌ ERROR fetching user profile: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                
                dispatchGroup.notify(queue: .main) {
                    print("📊 Processed all land assignments. Found \(successfulMatches) matches.")
                    completion(.success(matchedAssignments))
                }
            }
    }
    
    private func performLandSearch(company: String, fleet: String, month: Int, completion: @escaping (Result<[LandAssignment], Error>) -> Void) {
        // Calculate date range for a wider window (month ± 2)
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        
        // Start with two months before
        var startDateComponents = DateComponents()
        startDateComponents.year = currentYear
        startDateComponents.month = max(1, month - 2)  // Don't go below January
        startDateComponents.day = 1
        
        // End two months after
        var endDateComponents = DateComponents()
        endDateComponents.year = currentYear
        endDateComponents.month = min(12, month + 3)  // Don't go beyond December (+3 because we need the start of the month after)
        endDateComponents.day = 1
        
        guard let startDate = calendar.date(from: startDateComponents),
              let endMonthStart = calendar.date(from: endDateComponents) else {
            print("❌ ERROR: Invalid date calculation in searchCompatibleLandAssignments")
            completion(.failure(NSError(domain: "FirebaseService", code: 100, userInfo: [NSLocalizedDescriptionKey: "Invalid date"])))
            return
        }
        
        // Get the end date (day before the start of the next month)
        let endDate = calendar.date(byAdding: .day, value: -1, to: endMonthStart) ?? endMonthStart
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        print("📅 Using WIDER date window: \(dateFormatter.string(from: startDate)) to \(dateFormatter.string(from: endDate)) (target month: \(month))")
        
        // Query for all land assignments with matching company
        print("📡 Querying Firestore for public land assignments")
        
        // Default company if empty
        let searchCompany = company.isEmpty ? AppConstants.defaultCompany.lowercased() : company.lowercased()
        
        db.collection("landAssignments")
            .whereField("isPublic", isEqualTo: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ ERROR querying land assignments: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("ℹ️ No public land assignments found")
                    completion(.success([]))
                    return
                }
                
                print("📊 Found \(documents.count) public land assignments. Processing...")
                
                var matchedAssignments: [LandAssignment] = []
                let dispatchGroup = DispatchGroup()
                var successfulMatches = 0
                
                // Process each land assignment
                for document in documents {
                    let data = document.data()
                    
                    // Extract user identifier
                    guard let uid = data["userIdentifier"] as? String else { continue }
                    
                    // Skip if this is the current user's assignment
                    if uid == self.getCurrentUserId() { continue }
                    
                    // Check if the expected joining date is within our window
                    var dateMatch = false
                    if let expectedJoiningTimestamp = data["expectedJoiningDate"] as? Timestamp {
                        let joiningDate = expectedJoiningTimestamp.dateValue()
                        
                        // Check if joining date is within our window
                        dateMatch = (joiningDate >= startDate && joiningDate <= endDate)
                        
                        print("📅 Expected joining date: \(joiningDate.formatted(date: .long, time: .omitted)) - \(dateMatch ? "✅ within window" : "❌ outside window")")
                    }
                    
                    if dateMatch {
                        dispatchGroup.enter()
                        
                        self.fetchUserProfileById(userId: uid) { userResult in
                            defer { dispatchGroup.leave() }
                            
                            switch userResult {
                            case .success(let userData):
                                // Fleet from land assignment
                                let landFleet = (data["fleetType"] as? String ?? "").lowercased()
                                let userRank = userData["presentRank"] as? String ?? ""
                                
                                print("👤 User \(uid) - Fleet: '\(landFleet)', Rank: '\(userRank)'")
                                
                                // Fleet compatibility check
                                let fleetMatch = fleet.isEmpty || fleet.lowercased().contains(landFleet) || landFleet.contains(fleet.lowercased())
                                
                                // Company compatibility check - if company is empty, use default company
                                let userCompany = (userData["company"] as? String ?? AppConstants.defaultCompany).lowercased()
                                let landCompany = (data["company"] as? String ?? userCompany).lowercased()
                                
                                // More flexible company matching - either exact match or contains
                                let companyMatch = searchCompany.isEmpty || 
                                                  searchCompany == landCompany || 
                                                  searchCompany.contains(landCompany) ||
                                                  landCompany.contains(searchCompany)
                                
                                print("🔍 Company match: \(companyMatch ? "✅" : "❌") - Fleet match: \(fleetMatch ? "✅" : "❌")")
                                
                                if companyMatch && fleetMatch {
                                    print("✅ Company/Fleet MATCH - \(searchCompany) / \(fleet.lowercased())")
                                    
                                    let assignment = LandAssignment()
                                    assignment.id = UUID()
                                    assignment.userIdentifier = uid
                                    assignment.fleetType = data["fleetType"] as? String
                                    assignment.lastVessel = data["lastVessel"] as? String
                                    assignment.email = data["email"] as? String
                                    assignment.mobileNumber = data["mobileNumber"] as? String
                                    assignment.isPublic = data["isPublic"] as? Bool ?? false
                                    assignment.company = data["company"] as? String
                                    
                                    // Convert timestamps to dates
                                    if let timestamp = data["dateHome"] as? Timestamp {
                                        assignment.dateHome = timestamp.dateValue()
                                    }
                                    
                                    if let timestamp = data["expectedJoiningDate"] as? Timestamp {
                                        assignment.expectedJoiningDate = timestamp.dateValue()
                                    }
                                    
                                    // Add user information to the assignment
                                    let user = User()
                                    user.userIdentifier = uid
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
                                    successfulMatches += 1
                                    print("🎯 MATCH FOUND: User \(user.name ?? "") \(user.surname ?? "") with rank \(user.presentRank ?? "Unknown")")
                                } else {
                                    print("❌ Company/Fleet MISMATCH - \(searchCompany) / \(fleet.lowercased()) vs \(landCompany) / \(landFleet)")
                                }
                                
                            case .failure(let error):
                                print("❌ ERROR fetching user profile: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                
                dispatchGroup.notify(queue: .main) {
                    print("📊 Processed all land assignments. Found \(successfulMatches) matches.")
                    completion(.success(matchedAssignments))
                }
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
                    user.company = data["company"] as? String ?? AppConstants.defaultCompany
                    
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
            case .success(_):
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
    
    // MARK: - Assignment Status Transition
    
    func changeUserAssignmentStatus(from: UserStatus, to: UserStatus, userId: String, newAssignment: Any, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🔄 Changing user \(userId) status from \(from) to \(to)")
        
        // 1. Update user status in Firestore
        db.collection("users").document(userId).updateData([
            "currentStatus": to.rawValue
        ]) { error in
            if let error = error {
                print("❌ Failed to update user status: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            print("✅ Successfully updated user status in Firestore")
            
            // 2. Delete ALL old assignments and create new one
            let dispatchGroup = DispatchGroup()
            
            if from == .onLand && to == .onShip {
                print("🔄 Transitioning from LAND to SHIP")
                // Deleting ALL land assignments
                dispatchGroup.enter()
                self.deleteAllUserAssignments(userId: userId, collectionName: "landAssignments") { result in
                    defer { dispatchGroup.leave() }
                    switch result {
                    case .success(let count):
                        print("✅ Successfully deleted \(count) land assignments")
                    case .failure(let error):
                        print("⚠️ Error deleting land assignments: \(error.localizedDescription)")
                    }
                }
                
                // Creating ship assignment
                if let shipAssignment = newAssignment as? ShipAssignment {
                    dispatchGroup.enter()
                    print("📝 Creating new ship assignment")
                    self.saveShipAssignment(shipAssignment: shipAssignment) { result in
                        defer { dispatchGroup.leave() }
                        
                        switch result {
                        case .success(let id):
                            print("✅ Successfully created ship assignment with ID: \(id)")
                        case .failure(let error):
                            print("❌ Failed to save ship assignment: \(error.localizedDescription)")
                        }
                    }
                } else {
                    print("❌ Invalid ship assignment object provided")
                }
            } else if from == .onShip && to == .onLand {
                print("🔄 Transitioning from SHIP to LAND")
                // Deleting ALL ship assignments
                dispatchGroup.enter()
                self.deleteAllUserAssignments(userId: userId, collectionName: "shipAssignments") { result in
                    defer { dispatchGroup.leave() }
                    switch result {
                    case .success(let count):
                        print("✅ Successfully deleted \(count) ship assignments")
                    case .failure(let error):
                        print("⚠️ Error deleting ship assignments: \(error.localizedDescription)")
                    }
                }
                
                // Creating land assignment
                if let landAssignment = newAssignment as? LandAssignment {
                    dispatchGroup.enter()
                    print("📝 Creating new land assignment")
                    self.saveLandAssignment(landAssignment: landAssignment) { result in
                        defer { dispatchGroup.leave() }
                        
                        switch result {
                        case .success(let id):
                            print("✅ Successfully created land assignment with ID: \(id)")
                        case .failure(let error):
                            print("❌ Failed to save land assignment: \(error.localizedDescription)")
                        }
                    }
                } else {
                    print("❌ Invalid land assignment object provided")
                }
            }
            
            dispatchGroup.notify(queue: .main) {
                print("✅ Assignment status change complete")
                completion(.success(()))
            }
        }
    }
    
    // Function to delete all user assignments of a given type 
    // If keepOne is true, it will preserve the most recent assignment
    func deleteAllUserAssignments(userId: String, collectionName: String = "shipAssignments", keepOne: Bool = false, completion: @escaping (Result<Int, Error>) -> Void) {
        print("🗑️ Attempting to delete \(keepOne ? "all but one" : "all") \(collectionName) for user \(userId)")
        
        db.collection(collectionName)
            .whereField("userIdentifier", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error getting assignments: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    print("ℹ️ No assignments found to delete")
                    completion(.success(0))
                    return
                }
                
                print("🗑️ Found \(documents.count) assignments to process")
                
                // If we need to keep one assignment, sort by creation date and skip the most recent
                var documentsToDelete = documents
                if keepOne && documents.count > 1 {
                    // Sort documents by creation date (newest first)
                    documentsToDelete = documents.sorted { 
                        let date1 = ($0.data()["dateCreated"] as? Timestamp)?.dateValue() ?? Date.distantPast
                        let date2 = ($1.data()["dateCreated"] as? Timestamp)?.dateValue() ?? Date.distantPast
                        return date1 > date2
                    }
                    
                    // Remove the most recent document from the deletion list
                    let keptDoc = documentsToDelete.removeFirst()
                    print("✅ Keeping most recent assignment (created \((keptDoc.data()["dateCreated"] as? Timestamp)?.dateValue().formatted() ?? "unknown date"))")
                }
                
                let batch = self.db.batch()
                
                for document in documentsToDelete {
                    batch.deleteDocument(document.reference)
                }
                
                batch.commit { error in
                    if let error = error {
                        print("❌ Error deleting assignments: \(error.localizedDescription)")
                        completion(.failure(error))
                    } else {
                        print("✅ Successfully deleted \(documentsToDelete.count) assignments")
                        completion(.success(documentsToDelete.count))
                    }
                }
            }
    }
    
    // Debug function to check authentication status
    func printAuthStatus() {
        if let user = Auth.auth().currentUser {
            print("✅ Current user authenticated: \(user.uid)")
            user.getIDTokenResult { result, error in
                if let error = error {
                    print("❌ Error getting token: \(error.localizedDescription)")
                    return
                }
                
                if let result = result {
                    print("📝 Token expires: \(result.expirationDate)")
                    print("📝 Authentication time: \(result.authDate)")
                    print("📝 Is admin: \(result.claims["admin"] as? Bool ?? false)")
                }
            }
        } else {
            print("❌ No user authenticated!")
        }
    }
    
    // Helper method to fetch a specific user's profile
    func fetchUserProfileById(userId: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        print("📊 Attempting to fetch user profile for ID: \(userId)")
        guard !userId.isEmpty else {
            print("❌ Error: Empty userId provided to fetchUserProfileById")
            completion(.failure(NSError(domain: "FirebaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty user ID"])))
            return
        }

        // Use get() instead of a listener
        print("📡 Sending one-time get() request to Firestore for user: \(userId)")
        db.collection("users").document(userId).getDocument { document, error in
            if let error = error {
                print("❌ Firestore error fetching user \(userId): \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let document = document else {
                print("❌ Document is nil for user \(userId)")
                completion(.failure(NSError(domain: "FirebaseService", code: 2, userInfo: [NSLocalizedDescriptionKey: "User profile not found"])))
                return
            }
            
            guard document.exists else {
                print("❌ Document does not exist for user \(userId)")
                completion(.failure(NSError(domain: "FirebaseService", code: 2, userInfo: [NSLocalizedDescriptionKey: "User profile not found"])))
                return
            }
            
            guard let data = document.data() else {
                print("❌ Document data is nil for user \(userId)")
                completion(.failure(NSError(domain: "FirebaseService", code: 2, userInfo: [NSLocalizedDescriptionKey: "User profile not found"])))
                return
            }
            
            print("✅ Successfully fetched profile for user \(userId)")
            completion(.success(data))
        }
    }
    
    /// Checks for and cleans up duplicate user assignments
    /// - Parameters:
    ///   - userId: The user ID to check assignments for
    ///   - completion: Callback with whether user has active assignments and any error
    public func checkExistingUserAssignments(userId: String, completion: @escaping (Bool, Error?) -> Void) {
        print("🔍 Checking and cleaning up user assignments for \(userId)")
        
        // First clean up any duplicate assignments
        cleanupDuplicateUserAssignments(userId: userId) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                print("⚠️ Error cleaning up duplicate assignments: \(error.localizedDescription)")
                // Continue with assignment check even if cleanup fails
            }
            
            // Get user profile to determine current status
            self.getUserProfile(userId: userId) { result in
                switch result {
                case .success(let userProfile):
                    let isOnShip = userProfile.currentStatus == .onShip
                    let collectionName = isOnShip ? "shipAssignments" : "landAssignments"
                    
                    print("👤 User is currently \(isOnShip ? "on ship" : "on land"), checking \(collectionName)")
                    
                    // Check if there's at least one active assignment
                    self.db.collection(collectionName)
                        .whereField("userIdentifier", isEqualTo: userId)
                        .limit(to: 1)
                        .getDocuments { snapshot, error in
                            if let error = error {
                                print("❌ Error checking assignments: \(error.localizedDescription)")
                                completion(false, error)
                                return
                            }
                            
                            let hasAssignments = !(snapshot?.documents.isEmpty ?? true)
                            print("✅ Assignment check complete: user \(hasAssignments ? "has" : "does not have") active assignments")
                            completion(hasAssignments, nil)
                        }
                    
                case .failure(let error):
                    print("❌ Error fetching user profile: \(error.localizedDescription)")
                    completion(false, error)
                }
            }
        }
    }
    
    /// Cleans up duplicate assignments for a user, keeping only the most recent one of each type
    /// - Parameters:
    ///   - userId: The user ID to clean up assignments for
    ///   - completion: Callback with any error that occurred
    public func cleanupDuplicateUserAssignments(userId: String, completion: @escaping (Error?) -> Void) {
        print("🧹 Cleaning up duplicate user assignments for \(userId)")
        
        let group = DispatchGroup()
        var errorEncountered: Error?
        var totalCleaned = 0
        
        // Clean up ship assignments
        group.enter()
        deleteAllUserAssignments(userId: userId, collectionName: "shipAssignments", keepOne: true) { result in
            switch result {
            case .success(let count):
                print("🚢 Cleaned up \(count) duplicate ship assignments")
                totalCleaned += count
            case .failure(let error):
                print("❌ Error cleaning ship assignments: \(error.localizedDescription)")
                errorEncountered = error
            }
            group.leave()
        }
        
        // Clean up land assignments
        group.enter()
        deleteAllUserAssignments(userId: userId, collectionName: "landAssignments", keepOne: true) { result in
            switch result {
            case .success(let count):
                print("🏠 Cleaned up \(count) duplicate land assignments")
                totalCleaned += count
            case .failure(let error):
                print("❌ Error cleaning land assignments: \(error.localizedDescription)")
                errorEncountered = error
            }
            group.leave()
        }
        
        group.notify(queue: .main) {
            print("🧹 Assignment cleanup complete: removed \(totalCleaned) duplicate assignments")
            completion(errorEncountered)
        }
    }
    
    /// Updates the user's last device login timestamp in Firestore
    /// - Parameters:
    ///   - userId: The user ID to update
    ///   - completion: Callback with any error that occurred
    public func updateLastDeviceLogin(userId: String, completion: @escaping (Error?) -> Void) {
        print("📱 Updating last device login timestamp for user \(userId)")
        
        // Get current timestamp
        let timestamp = Timestamp(date: Date())
        
        // Update the user document with the last login timestamp
        db.collection("users").document(userId).updateData([
            "lastDeviceLogin": timestamp,
            "lastDeviceId": UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        ]) { error in
            if let error = error {
                print("❌ Error updating last device login: \(error.localizedDescription)")
                completion(error)
            } else {
                print("✅ Successfully updated last device login timestamp")
                completion(nil)
            }
        }
    }
    
    /// Fetches user assignments from a specified collection
    /// - Parameters:
    ///   - userId: The user ID to fetch assignments for
    ///   - collectionName: The collection to fetch from (shipAssignments or landAssignments)
    ///   - completion: Callback with the fetched assignments or error
    func fetchUserAssignments(userId: String, collectionName: String, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        let db = Firestore.firestore()
        
        print("Fetching \(collectionName) for user: \(userId)")
        
        db.collection(collectionName)
            .whereField("userIdentifier", isEqualTo: userId)
            .getDocuments { (querySnapshot, error) in
                
                if let error = error {
                    print("Error fetching assignments: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    print("No \(collectionName) found for user: \(userId)")
                    completion(.success([]))
                    return
                }
                
                print("Found \(documents.count) \(collectionName) for user: \(userId)")
                let assignments = documents.map { $0.data() }
                completion(.success(assignments))
            }
    }
    
    /// Fetches and converts a user profile to a User model
    /// - Parameters:
    ///   - userId: The user ID to fetch
    ///   - completion: Callback with the User object or error
    private func getUserProfile(userId: String, completion: @escaping (Result<User, Error>) -> Void) {
        fetchUserProfileById(userId: userId) { result in
            switch result {
            case .success(let userData):
                let user = User()
                user.userIdentifier = userId
                user.name = userData["name"] as? String
                user.surname = userData["surname"] as? String
                user.email = userData["email"] as? String
                user.mobileNumber = userData["mobileNumber"] as? String
                user.fleetWorking = userData["fleetWorking"] as? String
                user.presentRank = userData["presentRank"] as? String
                user.company = userData["company"] as? String ?? AppConstants.defaultCompany
                
                if let statusString = userData["currentStatus"] as? String,
                   let status = UserStatus(rawValue: statusString) {
                    user.currentStatus = status
                }
                
                completion(.success(user))
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Deletes a user's account and all associated data from Firebase
    /// - Parameters:
    ///   - password: The user's current password for re-authentication
    ///   - completion: Callback with either success or error
    func deleteUserAccount(password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🗑️ Starting account deletion process")
        
        // 1. First get the current Firebase user
        guard let currentUser = Auth.auth().currentUser else {
            let error = NSError(domain: "FirebaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not logged in or session expired"])
            print("❌ Error: User not logged in")
            completion(.failure(error))
            return
        }
        
        guard let email = currentUser.email else {
            let error = NSError(domain: "FirebaseService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not retrieve user email"])
            print("❌ Error: Missing email for current user")
            completion(.failure(error))
            return
        }
        
        let userId = currentUser.uid
        print("👤 Found user \(userId) with email \(email)")
        
        // 2. Re-authenticate the user (required for sensitive operations)
        print("🔐 Attempting to reauthenticate user")
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        
        currentUser.reauthenticate(with: credential) { [weak self] authResult, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Re-authentication failed: \(error.localizedDescription)")
                
                // Provide more specific error messages based on error code
                let nsError = error as NSError
                var errorMessage = "Authentication failed. Please check your password and try again."
                
                if nsError.domain == AuthErrorDomain {
                    switch nsError.code {
                    case AuthErrorCode.wrongPassword.rawValue:
                        errorMessage = "Incorrect password. Please try again."
                    case AuthErrorCode.tooManyRequests.rawValue:
                        errorMessage = "Too many attempts. Please try again later."
                    case AuthErrorCode.networkError.rawValue:
                        errorMessage = "Network error. Please check your connection."
                    default:
                        errorMessage = "Authentication error: \(error.localizedDescription)"
                    }
                }
                
                let customError = NSError(domain: "FirebaseService", code: 3, 
                                         userInfo: [NSLocalizedDescriptionKey: errorMessage])
                completion(.failure(customError))
                return
            }
            
            print("✅ User re-authenticated successfully")
            
            // 3. Delete user data in a specific order
            print("🗑️ Starting deletion of user data")
            self.deleteAllUserData(userId: userId) { error in
                if let error = error {
                    print("⚠️ Warning: Error deleting user data: \(error.localizedDescription)")
                    print("Continuing with account deletion anyway...")
                    // We continue anyway to delete the auth account
                }
                
                // Finally delete the authentication account
                print("🗑️ Deleting user authentication record")
                currentUser.delete { error in
                    if let error = error {
                        print("❌ Error deleting authentication account: \(error.localizedDescription)")
                        completion(.failure(error))
                        return
                    }
                    
                    print("✅ User account successfully deleted")
                    // Clear UserDefaults
                    UserDefaults.standard.removeObject(forKey: "userId")
                    UserDefaults.standard.removeObject(forKey: "isUserRegistered")
                    
                    completion(.success(()))
                }
            }
        }
    }
    
    /// Helper function to delete all user data from Firestore
    /// - Parameters:
    ///   - userId: The user ID to delete data for
    ///   - completion: Callback with any error that occurred
    private func deleteAllUserData(userId: String, completion: @escaping (Error?) -> Void) {
        print("🗑️ Deleting all user data for user \(userId)")
        
        let dispatchGroup = DispatchGroup()
        var encounteredError: Error?
        
        // 1. Delete ship assignments
        dispatchGroup.enter()
        deleteAllUserAssignments(userId: userId, collectionName: "shipAssignments", keepOne: false) { result in
            switch result {
            case .success(let count):
                print("✅ Deleted \(count) ship assignments")
            case .failure(let error):
                print("❌ Error deleting ship assignments: \(error.localizedDescription)")
                encounteredError = error
            }
            dispatchGroup.leave()
        }
        
        // 2. Delete land assignments
        dispatchGroup.enter()
        deleteAllUserAssignments(userId: userId, collectionName: "landAssignments", keepOne: false) { result in
            switch result {
            case .success(let count):
                print("✅ Deleted \(count) land assignments")
            case .failure(let error):
                print("❌ Error deleting land assignments: \(error.localizedDescription)")
                encounteredError = error
            }
            dispatchGroup.leave()
        }
        
        // 3. Delete user document
        dispatchGroup.enter()
        db.collection("users").document(userId).delete { error in
            if let error = error {
                print("❌ Error deleting user document: \(error.localizedDescription)")
                encounteredError = error
            } else {
                print("✅ User document deleted")
            }
            dispatchGroup.leave()
        }
        
        // 4. Delete user profile photo from storage
        dispatchGroup.enter()
        let photoRef = storage.reference().child("users/\(userId)/profile.jpg")
        photoRef.delete { error in
            // It's okay if the photo doesn't exist or can't be deleted
            if let error = error {
                print("ℹ️ Photo deletion result: \(error.localizedDescription)")
            } else {
                print("✅ User profile photo deleted")
            }
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .main) {
            print("🗑️ All user data deletion complete")
            completion(encounteredError)
        }
    }
} 
