import Foundation

/// 阶段 B 的内存 Adapter，同时也是后续 Application 集成测试使用的真实 Repository 实现。
actor InMemoryTrainingRepository: TrainingRepository {
    private struct Receipt: Sendable {
        let request: IdempotencyRequest
        let value: RepositoryStoredValue
    }

    private var plans: [UUID: DailyPlan] = [:]
    private var sessions: [UUID: WorkoutSession] = [:]
    private var receipts: [UUID: Receipt] = [:]
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func loadDay(on date: Date) -> TrainingDayData {
        let dayPlans = plans.values
            .filter { calendar.isDate($0.scheduledDate, inSameDayAs: date) }
            .sorted { $0.createdAt < $1.createdAt }
        let planIDs = Set(dayPlans.map(\.id))
        let daySessions = sessions.values.filter { planIDs.contains($0.sourcePlanID) }
        return TrainingDayData(
            plans: dayPlans,
            activeSession: daySessions.first { $0.status == .inProgress },
            finishedSessions: daySessions
                .filter { $0.status != .inProgress }
                .sorted { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) }
        )
    }

    func loadPlan(id: UUID) -> DailyPlan? {
        plans[id]
    }

    func loadActiveSession() -> WorkoutSession? {
        sessions.values.first { $0.status == .inProgress }
    }

    func loadSession(id: UUID) -> WorkoutSession? {
        sessions[id]
    }

    func replay(_ request: IdempotencyRequest) throws -> RepositoryStoredValue? {
        guard let receipt = receipts[request.key] else { return nil }
        guard receipt.request == request else {
            throw TrainingRepositoryError.idempotencyKeyConflict
        }
        return receipt.value
    }

    func createPlan(
        _ plan: DailyPlan,
        idempotency: IdempotencyRequest
    ) throws -> IdempotentWrite<DailyPlan> {
        if let replayed = try replay(idempotency) {
            guard case let .plan(stored) = replayed else {
                throw TrainingRepositoryError.unexpectedStoredResult
            }
            return IdempotentWrite(value: stored, wasReplayed: true)
        }
        let hasPlanOnDay = plans.values.contains {
            $0.status != .archived
                && calendar.isDate($0.scheduledDate, inSameDayAs: plan.scheduledDate)
        }
        guard !hasPlanOnDay else {
            throw TrainingRepositoryError.activePlanAlreadyExists
        }
        plans[plan.id] = plan
        receipts[idempotency.key] = Receipt(request: idempotency, value: .plan(plan))
        return IdempotentWrite(value: plan, wasReplayed: false)
    }

    func updatePlan(
        _ plan: DailyPlan,
        expectedRevision: Int,
        idempotency: IdempotencyRequest
    ) throws -> IdempotentWrite<DailyPlan> {
        if let replayed = try replay(idempotency) {
            guard case let .plan(stored) = replayed else {
                throw TrainingRepositoryError.unexpectedStoredResult
            }
            return IdempotentWrite(value: stored, wasReplayed: true)
        }
        guard let current = plans[plan.id] else {
            throw TrainingRepositoryError.planNotFound
        }
        guard current.revision == expectedRevision else {
            throw TrainingRepositoryError.staleRevision
        }
        let conflictsWithAnotherPlan = plans.values.contains {
            $0.id != plan.id
                && $0.status != .archived
                && calendar.isDate($0.scheduledDate, inSameDayAs: plan.scheduledDate)
        }
        guard !conflictsWithAnotherPlan else {
            throw TrainingRepositoryError.activePlanAlreadyExists
        }
        plans[plan.id] = plan
        receipts[idempotency.key] = Receipt(request: idempotency, value: .plan(plan))
        return IdempotentWrite(value: plan, wasReplayed: false)
    }

    func startSession(
        _ session: WorkoutSession,
        expectedPlanRevision: Int,
        idempotency: IdempotencyRequest
    ) throws -> IdempotentWrite<WorkoutSession> {
        if let replayed = try replay(idempotency) {
            guard case let .session(stored) = replayed else {
                throw TrainingRepositoryError.unexpectedStoredResult
            }
            return IdempotentWrite(value: stored, wasReplayed: true)
        }
        guard let currentPlan = plans[session.sourcePlanID] else {
            throw TrainingRepositoryError.planNotFound
        }
        guard currentPlan.revision == expectedPlanRevision else {
            throw TrainingRepositoryError.staleRevision
        }
        guard currentPlan.status == .confirmed else {
            throw TrainingRepositoryError.planNotConfirmed
        }
        guard !sessions.values.contains(where: { $0.status == .inProgress }) else {
            throw TrainingRepositoryError.activeWorkoutAlreadyExists
        }
        sessions[session.id] = session
        receipts[idempotency.key] = Receipt(request: idempotency, value: .session(session))
        return IdempotentWrite(value: session, wasReplayed: false)
    }

    func updateSession(
        _ session: WorkoutSession,
        expectedRevision: Int,
        idempotency: IdempotencyRequest
    ) throws -> IdempotentWrite<WorkoutSession> {
        if let replayed = try replay(idempotency) {
            guard case let .session(stored) = replayed else {
                throw TrainingRepositoryError.unexpectedStoredResult
            }
            return IdempotentWrite(value: stored, wasReplayed: true)
        }
        guard let current = sessions[session.id] else {
            throw TrainingRepositoryError.workoutNotFound
        }
        guard current.revision == expectedRevision else {
            throw TrainingRepositoryError.staleRevision
        }
        sessions[session.id] = session
        receipts[idempotency.key] = Receipt(request: idempotency, value: .session(session))
        return IdempotentWrite(value: session, wasReplayed: false)
    }
}
