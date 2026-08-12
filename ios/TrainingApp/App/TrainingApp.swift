import SwiftUI

@main
struct TrainingApp: App {
    private let dependencies = DependencyContainer.live()

    var body: some Scene {
        WindowGroup {
            dependencies.makeRootView()
        }
    }
}
