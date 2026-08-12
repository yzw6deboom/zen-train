import SwiftUI

struct AppRootView: View {
    let environment: AppEnvironment

    var body: some View {
        VStack(spacing: 12) {
            Text(environment.displayName)
                .font(.largeTitle.bold())
                .accessibilityIdentifier("app-root-title")

            Text("手动训练闭环 · 阶段 A")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
