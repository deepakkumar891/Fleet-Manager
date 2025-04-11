import SwiftUI
import SwiftData

// Create an enum to represent the tabs
enum AppTab {
    case home, matches, search, profile
}

// Create a class that will store the selected tab state
class TabSelection: ObservableObject {
    @Published var selectedTab: AppTab = .home
}

struct MainTabView: View {
    @AppStorage("userId") private var userId = ""
    @StateObject private var tabSelection = TabSelection()
    
    var body: some View {
        TabView(selection: $tabSelection.selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(AppTab.home)
            
            MatchesView()
                .tabItem {
                    Label("Matches", systemImage: "person.2.fill")
                }
                .tag(AppTab.matches)
            
            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(AppTab.search)
            
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(AppTab.profile)
        }
        .environmentObject(tabSelection)
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: [User.self, ShipAssignment.self, LandAssignment.self], inMemory: true)
} 