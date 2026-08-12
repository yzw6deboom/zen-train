import SwiftUI

@MainActor
final class DependencyContainer {
    let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    static func live() -> DependencyContainer {
        DependencyContainer(environment: .live)
    }

    func makeRootView() -> some View {
        AppRootView(environment: environment)
    }
}
