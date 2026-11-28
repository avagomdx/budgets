import SwiftUI
import UIKit
import Observation
import UserNotifications

/// Home Screen quick action: long-press the app icon → "New expense".
enum QuickActions {
    static let addExpenseType = "budget.add-expense"

    @MainActor
    static func register() {
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(
                type: addExpenseType,
                localizedTitle: "New expense",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "plus.circle"),
                userInfo: nil
            )
        ]
    }
}

@Observable
final class QuickActionState {
    static let shared = QuickActionState()
    var pendingAdd = false
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Show notifications (like budget alerts) also while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // App was cold-launched from the quick action.
        if options.shortcutItem?.type == QuickActions.addExpenseType {
            QuickActionState.shared.pendingAdd = true
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    // App was already running in the background.
    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let handled = shortcutItem.type == QuickActions.addExpenseType
        if handled {
            QuickActionState.shared.pendingAdd = true
        }
        completionHandler(handled)
    }
}
