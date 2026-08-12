/// 保存应用启动时需要的环境配置。
///
/// `Equatable` 让测试可以比较两个配置是否相同；`Sendable` 表示这个值可以安全地跨并发边界传递。
struct AppEnvironment: Equatable, Sendable {
    /// 展示给用户的产品名称。
    let displayName: String

    /// 正式运行应用时使用的默认配置。
    static let live = AppEnvironment(displayName: "ZenTrain")
}
