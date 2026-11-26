import SwiftUI
import SwiftData

@main
struct BudgetApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [BudgetCategory.self, Expense.self])
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("didSeedDefaults") private var didSeedDefaults = false
    @State private var showingAdd = false

    var body: some View {
        TabView {
            OverviewView(showingAdd: $showingAdd)
                .tabItem { Label("Overview", systemImage: "chart.pie.fill") }

            ExpensesView(showingAdd: $showingAdd)
                .tabItem { Label("Expenses", systemImage: "list.bullet.rectangle") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .sheet(isPresented: $showingAdd) {
            ExpenseFormView()
        }
        .onChange(of: QuickActionState.shared.pendingAdd, initial: true) { _, pending in
            if pending {
                showingAdd = true
                QuickActionState.shared.pendingAdd = false
            }
        }
        .task {
            if !didSeedDefaults {
                DefaultData.seedIfNeeded(context)
                didSeedDefaults = true
            }
            QuickActions.register()
        }
    }
}
