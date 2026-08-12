import Foundation

/// Domain 返回可定位的校验问题；页面如何把问题翻译成提示文字由 Feature 决定。
enum ValidationIssue: Equatable, Sendable {
    case emptyPlanTitle
    case missingExecutableActivity
    case emptyActivityName
    case invalidActivityOrder
    case invalidSegmentOrder
    case duplicateIdentifier
    case emptyStrengthSets
    case emptyCardioSegments
    case negativeRepetitions
    case negativeLoad
    case negativeRPE
    case negativeDuration
    case negativeDistance
    case confirmationRequired
}

/// 聚合内部的规则错误，不包含跨聚合查询和持久化失败。
enum DomainError: Error, Equatable, Sendable {
    case validation([ValidationIssue])
    case planNotConfirmed
    case workoutAlreadyFinished
    case segmentNotFound
    case segmentKindMismatch
    case finishBeforeStart
}
