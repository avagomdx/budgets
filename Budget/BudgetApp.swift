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
            BankConnection.self, BankAccountLink.self,
            CategoryRule.self, SavingsGoal.self,
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
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var bankMessage: String?
    @State private var isLocked = AppLock.isEnabled

    var body: some View {
        Group {
            if didCompleteSetup {
                MainView()
            } else {
                SetupWizardView()
            }
        }
        .overlay {
            if isLocked && lockEnabled {
                LockView {
                    isLocked = false
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && lockEnabled {
                isLocked = true
            }
        }
        .onOpenURL { url in
            guard BankLink.isCallback(url) else { return }
            Task {
                do {
                    bankMessage = try await BankLink.handleCallback(url, context: context)
                } catch {
                    bankMessage = error.localizedDescription
                }
            }
        }
        .alert("Bank connection",
               isPresented: Binding(get: { bankMessage != nil }, set: { if !$0 { bankMessage = nil } })) {
            Button("OK", role: .cancel) { bankMessage = nil }
        } message: {
            Text(bankMessage ?? "")
        }
    }
}

struct MainView: View {
    @Environment(\.modelContext) var context
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
                refresh()
            }
        }
        .task {
            QuickActions.register()
            refresh()
        }
    }
}

extension MainView {
    /// On every app start or return: make sure the period is up to date, sync the bank, plan notifications.
    func refresh() {
        PeriodManager.ensureCurrentPeriod(context: context)
        Notifications.reschedule(context: context)
        Task {
            await BankSync.syncIfNeeded(context: context)
            Notifications.reschedule(context: context)
        }
    }
}
