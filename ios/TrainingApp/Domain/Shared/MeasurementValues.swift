import Foundation

/// 重量单位与用户输入保持一致，避免把磅静默换算成公斤后丢失原始表达。
enum LoadUnit: String, Codable, Sendable {
    case kilogram
    case pound
}

/// 训练重量使用 `Decimal`，避免二进制浮点数给十进制输入带来不必要的近似误差。
struct Load: Equatable, Codable, Sendable {
    let value: Decimal
    let unit: LoadUnit
}

enum DistanceUnit: String, Codable, Sendable {
    case meter
    case kilometer
    case mile
}

struct Distance: Equatable, Codable, Sendable {
    let value: Decimal
    let unit: DistanceUnit
}
