import SwiftUI

@main
struct SnipsyApp: App {
    init() {
        PurchaseController.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
