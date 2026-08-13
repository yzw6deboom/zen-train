import Foundation

/// UI、测试和未来 Agent 共用的最高业务接口。
///
/// 调用方只提交 Command、读取 Snapshot，不需要了解 Repository、事务或持久化技术。
protocol TrainingApplication: Sendable {
    func execute(_ command: TrainingCommand) async throws -> TrainingMutation
    func today(on date: Date) async throws -> TodaySnapshot
    func activeWorkout() async throws -> WorkoutSnapshot?
    func record(sessionID: UUID) async throws -> TrainingRecord
    /// “记录”一级页使用的只读列表查询，不向 Presentation 暴露 Repository 或 SwiftData Entity。
    func recentRecords(limit: Int) async throws -> [TrainingRecordSummary]
}

enum TrainingMutation: Equatable, Sendable {
    case planSaved(PlanEditorSnapshot)
    case workoutStarted(WorkoutSnapshot)
    case workoutUpdated(WorkoutSnapshot)
    case workoutCompleted(sessionID: UUID)
}

/// Application 对调用方暴露结构化业务错误，Feature 再决定具体提示方式。
enum TrainingApplicationError: Error, Equatable, Sendable {
    case invalidPlan([ValidationIssue])
    case invalidWorkout([ValidationIssue])
    case activePlanAlreadyExists
    case planNotFound
    case planNotConfirmed
    case activeWorkoutAlreadyExists
    case workoutNotFound
    case workoutAlreadyFinished
    case workoutNotFinished
    case segmentNotFound
    case staleRevision
    case idempotencyKeyConflict
    case persistenceFailure
}
