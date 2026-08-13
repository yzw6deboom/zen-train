import Foundation

struct TrainingDayData: Equatable, Sendable {
    let plans: [DailyPlan]
    let activeSession: WorkoutSession?
    let finishedSessions: [WorkoutSession]
}

enum RepositoryCommandKind: String, Codable, Sendable {
    case createDailyPlan
    case updateDailyPlan
    case startWorkout
    case recordStrengthSet
    case recordCardioSegment
    case completeWorkout
}

/// Repository 使用完整编码后的命令识别“同一次重试”，不同 payload 复用 key 会被拒绝。
struct IdempotencyRequest: Equatable, Sendable {
    let key: UUID
    let commandKind: RepositoryCommandKind
    let payload: Data
}

enum RepositoryStoredValue: Equatable, Sendable {
    case plan(DailyPlan)
    case session(WorkoutSession)
}

struct IdempotentWrite<Value: Equatable & Sendable>: Equatable, Sendable {
    let value: Value
    let wasReplayed: Bool
}

enum TrainingRepositoryError: Error, Equatable, Sendable {
    case activePlanAlreadyExists
    case planNotFound
    case planNotConfirmed
    case activeWorkoutAlreadyExists
    case workoutNotFound
    case staleRevision
    case idempotencyKeyConflict
    case unexpectedStoredResult
}

/// Repository 的写方法把版本检查、业务唯一性检查、写入和幂等回执放在同一原子边界内。
protocol TrainingRepository: Sendable {
    func loadDay(on date: Date) async throws -> TrainingDayData
    func loadPlan(id: UUID) async throws -> DailyPlan?
    /// 读取某一不可变历史版本，供后续差异展示和撤销流程使用。
    func loadPlanRevision(planID: UUID, revision: Int) async throws -> DailyPlan?
    func loadActiveSession() async throws -> WorkoutSession?
    func loadSession(id: UUID) async throws -> WorkoutSession?
    func replay(_ request: IdempotencyRequest) async throws -> RepositoryStoredValue?

    func createPlan(
        _ plan: DailyPlan,
        idempotency: IdempotencyRequest
    ) async throws -> IdempotentWrite<DailyPlan>

    func updatePlan(
        _ plan: DailyPlan,
        expectedRevision: Int,
        idempotency: IdempotencyRequest
    ) async throws -> IdempotentWrite<DailyPlan>

    func startSession(
        _ session: WorkoutSession,
        expectedPlanRevision: Int,
        idempotency: IdempotencyRequest
    ) async throws -> IdempotentWrite<WorkoutSession>

    func updateSession(
        _ session: WorkoutSession,
        expectedRevision: Int,
        idempotency: IdempotencyRequest
    ) async throws -> IdempotentWrite<WorkoutSession>
}

/// 时间和随机 ID 是系统边界，注入协议后业务测试可以完全确定。
protocol TrainingClock: Sendable {
    func now() async -> Date
}

protocol IDGenerator: Sendable {
    func next() async -> UUID
}
