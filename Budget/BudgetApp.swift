import SwiftUI
import SwiftData

@main
struct BudgetApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// A new store name, so data from the first version is not carried over.
    static let container: ModelContainer = {
        let schema = Schema([
            BudgetCategory.self, Expense.self,
            IncomeSource.self, FixedCostTemplate.self,
            BudgetPeriod.self, IncomeEntry.self, PeriodFixedCost.self,
        ])
        let configuration = ModelConfiguration("BudgetV2", schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create the data store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Self.container)
    }
}

/// Shows the setup wizard until it has been completed, then the app itself.
struct RootView: View {
    static let setupKey = "didCompleteSetupV2"
    @AppStorage(RootView.setupKey) private var didCompleteSetup = false

    var body: some View {
        if didCompleteSetup {
            MainView()
        } else {
            SetupWizardView()
        }
    }
}

struct MainView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \BudgetPeriod.startDate) private var periods: [BudgetPeriod]
    @State private var showingAdd = false

    /// The current period, if its check-in hasn't been done yet.
    private var periodNeedingCheckIn: BudgetPeriod? {
        periods.last { $0.isCurrent && !$0.isCheckedIn }
    }

    var body: some View {
        TabView {
            OverviewView(showingAdd: $showingAdd)
                .tabItem { Label("Overview", systemImage: "chart.pie.fill") }

            ExpensesView(showingAdd: $showingAdd)
                .tabItem { Label("Expenses", systemImage: "list.bullet.rectangle") }

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .sheet(isPresented: $showingAdd) {
            ExpenseFormView()
        }
        .fullScreenCover(item: Binding(get: { periodNeedingCheckIn }, set: { _ in })) { period in
            CheckInView(period: period)
        }
        .onChange(of: QuickActionState.shared.pendingAdd, initial: true) { _, pending in
            if pending {
                showingAdd = true
                QuickActionState.shared.pendingAdd = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                PeriodManager.ensureCurrentPeriod(context: context)
            }
        }
        .task {
            PeriodManager.ensureCurrentPeriod(context: context)
            QuickActions.register()
        }
    }
}
