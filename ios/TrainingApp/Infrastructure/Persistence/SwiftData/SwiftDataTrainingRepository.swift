import Foundation
import SwiftData

/// 生产 Repository：每个写入在同一 ModelContext 中完成检查、保存与幂等回执。
actor SwiftDataTrainingRepository: TrainingRepository {
    private let modelContainer: ModelContainer
    private let calendar: Calendar

    init(modelContainer: ModelContainer, calendar: Calendar = .current) {
        self.modelContainer = modelContainer
        self.calendar = calendar
    }

    func loadDay(on date: Date) throws -> TrainingDayData {
        let context = ModelContext(modelContainer)
        let plans = try context.fetch(FetchDescriptor<DailyPlanEntity>())
            .filter { calendar.isDate($0.scheduledDate, inSameDayAs: date) }
            .sorted { $0.createdAt < $1.createdAt }
            .map(SwiftDataTrainingMapper.makePlan)
        let planIDs = Set(plans.map(\.id))
        let sessions = try context.fetch(FetchDescriptor<WorkoutSessionEntity>())
            .filter { planIDs.contains($0.sourcePlanID) }
            .map(SwiftDataTrainingMapper.makeSession)
        return TrainingDayData(
            plans: plans,
            activeSession: sessions.first { $0.status == .inProgress },
            finishedSessions: sessions.filter { $0.status != .inProgress }
                .sorted { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) }
        )
    }

    func loadPlan(id: UUID) throws -> DailyPlan? {
        let context = ModelContext(modelContainer)
        return try planEntity(id: id, context: context).map(SwiftDataTrainingMapper.makePlan)
    }

    func loadPlanRevision(planID: UUID, revision: Int) throws -> DailyPlan? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PlanRevisionEntity>(predicate: #Predicate {
            $0.plan?.id == planID && $0.revision == revision
        })
        return try context.fetch(descriptor).first.map { try SwiftDataTrainingMapper.makePlan(fromRevisionData: $0.snapshotData) }
    }

    func loadActiveSession() throws -> WorkoutSession? {
        let context = ModelContext(modelContainer)
        return try context.fetch(FetchDescriptor<WorkoutSessionEntity>())
            .first { $0.statusRawValue == WorkoutStatus.inProgress.rawValue }
            .map(SwiftDataTrainingMapper.makeSession)
    }

    func loadSession(id: UUID) throws -> WorkoutSession? {
        let context = ModelContext(modelContainer)
        return try sessionEntity(id: id, context: context).map(SwiftDataTrainingMapper.makeSession)
    }

    func replay(_ request: IdempotencyRequest) throws -> RepositoryStoredValue? {
        let context = ModelContext(modelContainer)
        guard let receipt = try receiptEntity(key: request.key, context: context) else { return nil }
        guard receipt.commandTypeRawValue == request.commandKind.rawValue, receipt.payload == request.payload else {
            throw TrainingRepositoryError.idempotencyKeyConflict
        }
        return try storedValue(from: receipt)
    }

    func createPlan(_ plan: DailyPlan, idempotency: IdempotencyRequest) throws -> IdempotentWrite<DailyPlan> {
        let context = ModelContext(modelContainer)
        if let replayed = try replay(idempotency, context: context) {
            guard case let .plan(value) = replayed else { throw TrainingRepositoryError.unexpectedStoredResult }
            return IdempotentWrite(value: value, wasReplayed: true)
        }
        let plans = try context.fetch(FetchDescriptor<DailyPlanEntity>())
        guard !plans.contains(where: { $0.statusRawValue != PlanStatus.archived.rawValue && calendar.isDate($0.scheduledDate, inSameDayAs: plan.scheduledDate) }) else { throw TrainingRepositoryError.activePlanAlreadyExists }
        context.insert(try SwiftDataTrainingMapper.makePlanEntity(plan))
        context.insert(try receipt(for: idempotency, value: .plan(plan)))
        try context.save()
        return IdempotentWrite(value: plan, wasReplayed: false)
    }

    func updatePlan(_ plan: DailyPlan, expectedRevision: Int, idempotency: IdempotencyRequest) throws -> IdempotentWrite<DailyPlan> {
        let context = ModelContext(modelContainer)
        if let replayed = try replay(idempotency, context: context) {
            guard case let .plan(value) = replayed else { throw TrainingRepositoryError.unexpectedStoredResult }
            return IdempotentWrite(value: value, wasReplayed: true)
        }
        guard let entity = try planEntity(id: plan.id, context: context) else { throw TrainingRepositoryError.planNotFound }
        guard entity.revision == expectedRevision else { throw TrainingRepositoryError.staleRevision }
        let plans = try context.fetch(FetchDescriptor<DailyPlanEntity>())
        guard !plans.contains(where: { $0.id != plan.id && $0.statusRawValue != PlanStatus.archived.rawValue && calendar.isDate($0.scheduledDate, inSameDayAs: plan.scheduledDate) }) else { throw TrainingRepositoryError.activePlanAlreadyExists }
        try SwiftDataTrainingMapper.update(entity, from: plan)
        context.insert(try receipt(for: idempotency, value: .plan(plan)))
        try context.save()
        return IdempotentWrite(value: plan, wasReplayed: false)
    }

    func startSession(_ session: WorkoutSession, expectedPlanRevision: Int, idempotency: IdempotencyRequest) throws -> IdempotentWrite<WorkoutSession> {
        let context = ModelContext(modelContainer)
        if let replayed = try replay(idempotency, context: context) {
            guard case let .session(value) = replayed else { throw TrainingRepositoryError.unexpectedStoredResult }
            return IdempotentWrite(value: value, wasReplayed: true)
        }
        guard let plan = try planEntity(id: session.sourcePlanID, context: context) else { throw TrainingRepositoryError.planNotFound }
        guard plan.revision == expectedPlanRevision else { throw TrainingRepositoryError.staleRevision }
        guard plan.statusRawValue == PlanStatus.confirmed.rawValue else { throw TrainingRepositoryError.planNotConfirmed }
        let sessions = try context.fetch(FetchDescriptor<WorkoutSessionEntity>())
        guard !sessions.contains(where: { $0.statusRawValue == WorkoutStatus.inProgress.rawValue }) else { throw TrainingRepositoryError.activeWorkoutAlreadyExists }
        context.insert(try SwiftDataTrainingMapper.makeSessionEntity(session))
        context.insert(try receipt(for: idempotency, value: .session(session)))
        try context.save()
        return IdempotentWrite(value: session, wasReplayed: false)
    }

    func updateSession(_ session: WorkoutSession, expectedRevision: Int, idempotency: IdempotencyRequest) throws -> IdempotentWrite<WorkoutSession> {
        let context = ModelContext(modelContainer)
        if let replayed = try replay(idempotency, context: context) {
            guard case let .session(value) = replayed else { throw TrainingRepositoryError.unexpectedStoredResult }
            return IdempotentWrite(value: value, wasReplayed: true)
        }
        guard let entity = try sessionEntity(id: session.id, context: context) else { throw TrainingRepositoryError.workoutNotFound }
        guard entity.revision == expectedRevision else { throw TrainingRepositoryError.staleRevision }
        try SwiftDataTrainingMapper.update(entity, from: session)
        context.insert(try receipt(for: idempotency, value: .session(session)))
        try context.save()
        return IdempotentWrite(value: session, wasReplayed: false)
    }

    private func replay(_ request: IdempotencyRequest, context: ModelContext) throws -> RepositoryStoredValue? {
        guard let receipt = try receiptEntity(key: request.key, context: context) else { return nil }
        guard receipt.commandTypeRawValue == request.commandKind.rawValue, receipt.payload == request.payload else { throw TrainingRepositoryError.idempotencyKeyConflict }
        return try storedValue(from: receipt)
    }

    private func planEntity(id: UUID, context: ModelContext) throws -> DailyPlanEntity? { try context.fetch(FetchDescriptor<DailyPlanEntity>(predicate: #Predicate { $0.id == id })).first }
    private func sessionEntity(id: UUID, context: ModelContext) throws -> WorkoutSessionEntity? { try context.fetch(FetchDescriptor<WorkoutSessionEntity>(predicate: #Predicate { $0.id == id })).first }
    private func receiptEntity(key: UUID, context: ModelContext) throws -> IdempotencyRecordEntity? { try context.fetch(FetchDescriptor<IdempotencyRecordEntity>(predicate: #Predicate { $0.key == key })).first }
    private func storedValue(from receipt: IdempotencyRecordEntity) throws -> RepositoryStoredValue {
        switch receipt.resultKindRawValue {
        case "plan": return .plan(try SwiftDataTrainingMapper.makePlan(fromRevisionData: receipt.resultData))
        case "session": return .session(try SwiftDataTrainingMapper.decodeSession(receipt.resultData))
        default: throw TrainingPersistenceError.invalidStoredData
        }
    }

    private func receipt(for request: IdempotencyRequest, value: RepositoryStoredValue) throws -> IdempotencyRecordEntity {
        let aggregateID: UUID
        let resultKind: String
        let resultData: Data
        switch value {
        case let .plan(plan): aggregateID = plan.id; resultKind = "plan"; resultData = try SwiftDataTrainingMapper.encode(plan)
        case let .session(session): aggregateID = session.id; resultKind = "session"; resultData = try SwiftDataTrainingMapper.encode(session)
        }
        return IdempotencyRecordEntity(key: request.key, commandTypeRawValue: request.commandKind.rawValue, payload: request.payload, aggregateID: aggregateID, resultKindRawValue: resultKind, resultData: resultData, createdAt: Date())
    }
}
