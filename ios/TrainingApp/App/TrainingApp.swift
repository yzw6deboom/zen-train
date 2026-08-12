import SwiftUI

/// iOS 应用入口。
///
/// `@main` 告诉系统从这个类型启动应用；`App` 协议要求提供一个 `body` 来声明应用场景。
@main
struct TrainingApp: App {
    /// 应用启动时只创建一次组合根，后续页面从这里取得所需依赖。
    private let dependencies = DependencyContainer.live()

    /// `WindowGroup` 表示应用的主窗口，并把组合根生成的视图放进窗口中。
    var body: some Scene {
        WindowGroup {
            dependencies.makeRootView()
        }
    }
}
