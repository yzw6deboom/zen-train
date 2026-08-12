struct AppEnvironment: Equatable, Sendable {
    let displayName: String

    static let live = AppEnvironment(displayName: "ZenTrain")
}
