import SwiftUI

/// 应用的根视图。
///
/// 阶段 B 已完成业务内核，但真正的今日计划页面仍会在阶段 D 接入。
struct AppRootView: View {
    /// 根视图只读取展示所需的配置，不在 View 中创建业务服务或数据库。
    let environment: AppEnvironment

    /// `body` 描述当前视图的界面层级；状态变化时 SwiftUI 会重新计算它。
    var body: some View {
        VStack(spacing: 12) {
            Text(environment.displayName)
                .font(.largeTitle.bold())
                // UI 测试通过稳定标识查找控件，避免依赖可能变化的显示文字。
                .accessibilityIdentifier("app-root-title")

            Text("手动训练闭环 · 阶段 B 业务内核")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
