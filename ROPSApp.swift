import SwiftUI

/// Entry point for the app so the built binary can launch.
/// Without an `@main` `App` struct, the app installs but fails to open.
@main
struct ROPSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
