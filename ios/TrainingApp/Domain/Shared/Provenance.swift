import Foundation

/// 记录业务事实的来源；来源不同不能绕过同一套 Domain 校验。
enum OperationSource: String, Codable, Sendable {
    case manual
    case agent
    case voice
    case healthKit
    case system
}

/// 描述事实从哪里产生，以及是否已经获得用户确认。
struct Provenance: Equatable, Codable, Sendable {
    let source: OperationSource
    let confirmedByUser: Bool
    let sourceReference: String?
}
