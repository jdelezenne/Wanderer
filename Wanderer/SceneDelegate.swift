import UIKit
import SwiftUI
import SwiftData

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var modelContainer: ModelContainer?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            do {
                let container = try WandererPersistence.makeContainer()
                modelContainer = container
                let status = PersistenceStatus()
                window.rootViewController = UIHostingController(
                    rootView: ContentView(modelContext: container.mainContext, persistenceStatus: status)
                        .modelContainer(container)
                )
            } catch {
                window.rootViewController = UIHostingController(
                    rootView: PersistenceUnavailableView(message: error.localizedDescription)
                )
            }
            self.window = window
            window.makeKeyAndVisible()
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
    }

    func sceneWillResignActive(_ scene: UIScene) {
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
    }
}

private struct PersistenceUnavailableView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Wanderer Couldn’t Start", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("The app’s database couldn’t be opened. Your data has not been deleted.\n\n\(message)")
        }
        .padding()
    }
}
