//
//  Fleet_ManagerApp.swift
//  Fleet Manager
//
//  Created by Deepak Kumar on 30/03/2025.
//

import SwiftUI
import SwiftData
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct Fleet_ManagerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(sharedModelContainer)
        }
    }
    
    private var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            User.self,
            ShipAssignment.self,
            LandAssignment.self
        ])
        
        // Configure local storage without CloudKit
        do {
            print("Setting up SwiftData container...")
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("⚠️ Failed to create SwiftData container: \(error.localizedDescription)")
            
            // Last resort - in-memory storage
            do {
                print("Falling back to in-memory storage...")
                let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [memoryConfig])
            } catch {
                fatalError("Could not create any model container: \(error.localizedDescription)")
            }
        }
    }()
}

