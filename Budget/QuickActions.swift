import SwiftUI
import UIKit
import Observation

/// Snelle actie op het beginscherm: houd het app-icoon ingedrukt → "Nieuwe uitgave".
enum QuickActions {
    static let addExpenseType = "budget.add-expense"

    @MainActor
    static func register() {
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(
                type: addExpenseType,
                localizedTitle: "Nieuwe uitgave",
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

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // App werd koud gestart via de snelle actie.
        if options.shortcutItem?.type == QuickActions.addExpenseType {
            QuickActionState.shared.pendingAdd = true
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    // App draaide al op de achtergrond.
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
