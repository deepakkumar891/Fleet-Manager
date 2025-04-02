import SwiftUI
import SwiftData

struct MainTabView: View {
    @AppStorage("userId") private var userId = ""
    
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            
            MatchesView()
                .tabItem {
                    Label("Matches", systemImage: "person.2.fill")
                }
            
            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
            
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: [User.self, ShipAssignment.self, LandAssignment.self], inMemory: true)
} 