import SwiftUI

/// 应用的组合根，集中创建并装配具体依赖。
///
/// `@MainActor` 保证界面相关依赖只在主线程访问。后续加入 Repository 和 Application Service 时，
/// 具体实现仍应只在这里创建，Feature 和 View 只接收抽象接口。
@MainActor
final class DependencyContainer {
    /// 应用启动配置。
    let environment: AppEnvironment

    /// 允许测试传入自定义配置，而正式 App 使用 `live()` 创建默认配置。
    init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// 创建正式运行环境使用的依赖容器。
    static func live() -> DependencyContainer {
        DependencyContainer(environment: .live)
    }

    /// 从已经装配好的依赖创建根视图。
    func makeRootView() -> some View {
        AppRootView(environment: environment)
    }
}
