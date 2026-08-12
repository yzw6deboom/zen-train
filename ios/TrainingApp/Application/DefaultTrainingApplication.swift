import Foundation

/// 默认 Application Service 用 actor 串行组织命令。
///
/// actor 在 `await` 处仍可能重入，所以真正的版本检查、唯一性和幂等原子性继续由 Repository 保证。
actor DefaultTrainingApplication: TrainingApplication {
    private let repository: any TrainingRepository
    private let clock: any TrainingClock
    private let idGenerator: any IDGenerator

    init(
        repository: any TrainingRepository,
        clock: any TrainingClock,
        idGenerator: any IDGenerator
    ) {
        self.repository = repository
        self.clock = clock
        self.idGenerator = idGenerator
    }

    func execute(_ command: TrainingCommand) async throws -> TrainingMutation {
        do {
            let idempotency = try makeIdempotencyRequest(for: command)
            if let stored = try await repository.replay(idempotency) {
                return try mutation(for: command, stored: stored)
            }

            switch command {
            case let .createDailyPlan(command):
                return try await createDailyPlan(command, idempotency: idempotency)
            case let .updateDailyPlan(command):
                return try await updateDailyPlan(command, idempotency: idempotency)
            case let .startWorkout(command):
                return try await startWorkout(command, idempotency: idempotency)
            case let .recordStrengthSet(command):
                return try await recordStrengthSet(command, idempotency: idempotency)
            case let .recordCardioSegment(command):
                return try await recordCardioSegment(command, idempotency: idempotency)
            case let .completeWorkout(command):
                return try await completeWorkout(command, idempotency: idempotency)
            }
        } catch let error as TrainingApplicationError {
            throw error
        } catch let error as TrainingRepositoryError {
            throw mapRepositoryError(error)
        } catch {
            throw TrainingApplicationError.persistenceFailure
        }
    }

    func today(on date: Date) async throws -> TodaySnapshot {
        do {
            let day = try await repository.loadDay(on: date)
            let finished = day.finishedSessions.sorted {
                ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast)
            }
            let recentRecords = try finished.map(makeTrainingRecord).map {
                TrainingRecordSummary(
                    sessionID: $0.sessionID,
                    title: $0.title,
                    endedAt: $0.endedAt,
                    status: $0.status
                )
            }

            if let active = day.activeSession {
                return TodaySnapshot(
                    state: .workoutInProgress(makeWorkoutSnapshot(active)),
                    recentRecords: recentRecords
                )
            }
            if let latestFinished = finished.first {
                return TodaySnapshot(
                    state: .completed(try makeTrainingRecord(latestFinished)),
                    recentRecords: recentRecords
                )
            }
            guard let plan = day.plans.max(by: { $0.updatedAt < $1.updatedAt }) else {
                return TodaySnapshot(state: .noPlan, recentRecords: recentRecords)
            }
            let snapshot = makePlanSnapshot(plan)
            let state: TodayState = plan.status == .confirmed ? .ready(snapshot) : .draft(snapshot)
            return TodaySnapshot(state: state, recentRecords: recentRecords)
        } catch let error as TrainingApplicationError {
            throw error
        } catch {
            throw TrainingApplicationError.persistenceFailure
        }
    }

    func activeWorkout() async throws -> WorkoutSnapshot? {
        do {
            return try await repository.loadActiveSession().map(makeWorkoutSnapshot)
        } catch {
            throw TrainingApplicationError.persistenceFailure
        }
    }

    func record(sessionID: UUID) async throws -> TrainingRecord {
        do {
            guard let session = try await repository.loadSession(id: sessionID) else {
                throw TrainingApplicationError.workoutNotFound
            }
            return try makeTrainingRecord(session)
        } catch let error as TrainingApplicationError {
            throw error
        } catch {
            throw TrainingApplicationError.persistenceFailure
        }
    }

    private func createDailyPlan(
        _ command: CreateDailyPlanCommand,
        idempotency: IdempotencyRequest
    ) async throws -> TrainingMutation {
        let createdAt = await clock.now()
        let planID = await idGenerator.next()
        do {
            let activities = try await makeActivities(command.activities)
            let plan = try DailyPlan.create(
                id: planID,
                scheduledDate: command.scheduledDate,
                title: command.title,
                document: PlanDocument(rawText: command.rawDocument, notes: command.notes),
                activities: activities,
                status: command.confirmImmediately ? .confirmed : .draft,
                provenance: Provenance(
                    source: command.source,
                    confirmedByUser: true,
                    sourceReference: nil
                ),
                createdAt: createdAt
            )
            let write = try await repository.createPlan(plan, idempotency: idempotency)
            return .planSaved(makePlanSnapshot(write.value))
        } catch let DomainError.validation(issues) {
            throw TrainingApplicationError.invalidPlan(issues)
        }
    }

    private func updateDailyPlan(
        _ command: UpdateDailyPlanCommand,
        idempotency: IdempotencyRequest
    ) async throws -> TrainingMutation {
        guard var plan = try await repository.loadPlan(id: command.planID) else {
            throw TrainingApplicationError.planNotFound
        }
        guard plan.revision == command.expectedRevision else {
            throw TrainingApplicationError.staleRevision
        }

        let updatedAt = await clock.now()
        do {
            let activities = try await makeActivities(command.activities)
            try plan.revise(
                scheduledDate: command.scheduledDate,
                title: command.title,
                document: PlanDocument(rawText: command.rawDocument, notes: command.notes),
                activities: activities,
                status: command.confirmImmediately ? .confirmed : .draft,
                provenance: Provenance(
                    source: command.source,
                    confirmedByUser: true,
                    sourceReference: nil
                ),
                updatedAt: updatedAt
            )
            let write = try await repository.updatePlan(
                plan,
                expectedRevision: command.expectedRevision,
                idempotency: idempotency
            )
            return .planSaved(makePlanSnapshot(write.value))
        } catch let DomainError.validation(issues) {
            throw TrainingApplicationError.invalidPlan(issues)
        }
    }

    private func startWorkout(
        _ command: StartWorkoutCommand,
        idempotency: IdempotencyRequest
    ) async throws -> TrainingMutation {
        guard let plan = try await repository.loadPlan(id: command.planID) else {
            throw TrainingApplicationError.planNotFound
        }
        guard plan.revision == command.expectedRevision else {
            throw TrainingApplicationError.staleRevision
        }
        guard plan.status == .confirmed else {
            throw TrainingApplicationError.planNotConfirmed
        }

        let startedAt = await clock.now()
        let sessionID = await idGenerator.next()
        var identifiers: [PerformedActivityIdentifiers] = []
        for activity in plan.projection.activities {
            let activityID = await idGenerator.next()
            let segmentCount: Int
            switch activity.details {
            case let .strength(details): segmentCount = details.sets.count
            case let .cardio(details): segmentCount = details.segments.count
            }
            var segmentIDs: [UUID] = []
            for _ in 0..<segmentCount {
                segmentIDs.append(await idGenerator.next())
            }
            identifiers.append(
                PerformedActivityIdentifiers(activityID: activityID, segmentIDs: segmentIDs)
            )
        }

        do {
            let session = try WorkoutSession.start(
                id: sessionID,
                plan: plan,
                identifiers: identifiers,
                startedAt: startedAt
            )
            let write = try await repository.startSession(
                session,
                expectedPlanRevision: command.expectedRevision,
                idempotency: idempotency
            )
            return .workoutStarted(makeWorkoutSnapshot(write.value))
        } catch DomainError.planNotConfirmed {
            throw TrainingApplicationError.planNotConfirmed
        } catch let DomainError.validation(issues) {
            throw TrainingApplicationError.invalidWorkout(issues)
        }
    }

    private func recordStrengthSet(
        _ command: RecordStrengthSetCommand,
        idempotency: IdempotencyRequest
    ) async throws -> TrainingMutation {
        guard var session = try await repository.loadSession(id: command.sessionID) else {
            throw TrainingApplicationError.workoutNotFound
        }
        guard session.revision == command.expectedRevision else {
            throw TrainingApplicationError.staleRevision
        }
        do {
            try session.recordStrengthSet(
                id: command.performedSetID,
                actualRepetitions: command.actualRepetitions,
                actualLoad: command.actualLoad,
                actualRPE: command.actualRPE,
                note: command.note
            )
            let write = try await repository.updateSession(
                session,
                expectedRevision: command.expectedRevision,
                idempotency: idempotency
            )
            return .workoutUpdated(makeWorkoutSnapshot(write.value))
        } catch let DomainError.validation(issues) {
            throw TrainingApplicationError.invalidWorkout(issues)
        } catch DomainError.workoutAlreadyFinished {
            throw TrainingApplicationError.workoutAlreadyFinished
        } catch DomainError.segmentNotFound, DomainError.segmentKindMismatch {
            throw TrainingApplicationError.segmentNotFound
        }
    }

    private func recordCardioSegment(
        _ command: RecordCardioSegmentCommand,
        idempotency: IdempotencyRequest
    ) async throws -> TrainingMutation {
        guard var session = try await repository.loadSession(id: command.sessionID) else {
            throw TrainingApplicationError.workoutNotFound
        }
        guard session.revision == command.expectedRevision else {
            throw TrainingApplicationError.staleRevision
        }
        do {
            try session.recordCardioSegment(
                id: command.performedSegmentID,
                actualDurationSeconds: command.actualDurationSeconds,
                actualDistance: command.actualDistance,
                note: command.note
            )
            let write = try await repository.updateSession(
                session,
                expectedRevision: command.expectedRevision,
                idempotency: idempotency
            )
            return .workoutUpdated(makeWorkoutSnapshot(write.value))
        } catch let DomainError.validation(issues) {
            throw TrainingApplicationError.invalidWorkout(issues)
        } catch DomainError.workoutAlreadyFinished {
            throw TrainingApplicationError.workoutAlreadyFinished
        } catch DomainError.segmentNotFound, DomainError.segmentKindMismatch {
            throw TrainingApplicationError.segmentNotFound
        }
    }

    private func completeWorkout(
        _ command: CompleteWorkoutCommand,
        idempotency: IdempotencyRequest
    ) async throws -> TrainingMutation {
        guard var session = try await repository.loadSession(id: command.sessionID) else {
            throw TrainingApplicationError.workoutNotFound
        }
        guard session.revision == command.expectedRevision else {
            throw TrainingApplicationError.staleRevision
        }
        let endedAt = await clock.now()
        do {
            try session.finish(at: endedAt, feedback: command.feedback)
            let write = try await repository.updateSession(
                session,
                expectedRevision: command.expectedRevision,
                idempotency: idempotency
            )
            return .workoutCompleted(sessionID: write.value.id)
        } catch DomainError.workoutAlreadyFinished {
            throw TrainingApplicationError.workoutAlreadyFinished
        } catch DomainError.finishBeforeStart {
            throw TrainingApplicationError.invalidWorkout([])
        }
    }

    private func makeActivities(_ inputs: [PlannedActivityInput]) async throws -> [PlannedActivity] {
        var activities: [PlannedActivity] = []
        for (order, input) in inputs.enumerated() {
            let activityID = await resolvedID(input.id)
            let details: PlannedActivityDetails
            switch input.details {
            case let .strength(planInput):
                switch planInput {
                case let .uniform(setCount, target):
                    guard setCount > 0 else {
                        throw DomainError.validation([.emptyStrengthSets])
                    }
                    var setIDs: [UUID] = []
                    for _ in 0..<setCount { setIDs.append(await idGenerator.next()) }
                    details = .strength(
                        try StrengthPlan.expandingUniformTargets(
                            setIDs: setIDs,
                            repetitions: target.repetitions,
                            load: target.load,
                            rpe: target.rpe,
                            note: target.note
                        )
                    )
                case let .perSet(inputs):
                    var sets: [StrengthSetTarget] = []
                    for (setOrder, setInput) in inputs.enumerated() {
                        sets.append(
                            StrengthSetTarget(
                                id: await resolvedID(setInput.id),
                                order: setOrder + 1,
                                repetitions: setInput.repetitions,
                                load: setInput.load,
                                rpe: setInput.rpe,
                                note: setInput.note
                            )
                        )
                    }
                    details = .strength(StrengthPlan(sets: sets))
                }
            case let .cardio(planInput):
                var segments: [CardioSegmentTarget] = []
                for (segmentOrder, segmentInput) in planInput.segments.enumerated() {
                    segments.append(
                        CardioSegmentTarget(
                            id: await resolvedID(segmentInput.id),
                            order: segmentOrder + 1,
                            durationSeconds: segmentInput.durationSeconds,
                            distance: segmentInput.distance,
                            targetHeartRate: segmentInput.targetHeartRate,
                            note: segmentInput.note
                        )
                    )
                }
                details = .cardio(CardioPlan(segments: segments))
            }
            activities.append(
                PlannedActivity(
                    id: activityID,
                    order: order + 1,
                    name: input.name,
                    notes: input.notes,
                    details: details
                )
            )
        }
        return activities
    }

    private func resolvedID(_ existing: UUID?) async -> UUID {
        if let existing { return existing }
        return await idGenerator.next()
    }

    private func makeIdempotencyRequest(for command: TrainingCommand) throws -> IdempotencyRequest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return IdempotencyRequest(
            key: command.idempotencyKey,
            commandKind: command.repositoryKind,
            payload: try encoder.encode(command)
        )
    }

    private func mutation(
        for command: TrainingCommand,
        stored: RepositoryStoredValue
    ) throws -> TrainingMutation {
        switch (command, stored) {
        case (.createDailyPlan, let .plan(plan)), (.updateDailyPlan, let .plan(plan)):
            return .planSaved(makePlanSnapshot(plan))
        case (.startWorkout, let .session(session)):
            return .workoutStarted(makeWorkoutSnapshot(session))
        case (.recordStrengthSet, let .session(session)),
             (.recordCardioSegment, let .session(session)):
            return .workoutUpdated(makeWorkoutSnapshot(session))
        case (.completeWorkout, let .session(session)):
            return .workoutCompleted(sessionID: session.id)
        default:
            throw TrainingRepositoryError.unexpectedStoredResult
        }
    }

    private func makePlanSnapshot(_ plan: DailyPlan) -> PlanEditorSnapshot {
        PlanEditorSnapshot(
            id: plan.id,
            scheduledDate: plan.scheduledDate,
            title: plan.title,
            document: plan.document,
            activities: plan.projection.activities,
            status: plan.status,
            revision: plan.revision,
            provenance: plan.provenance
        )
    }

    private func makeWorkoutSnapshot(_ session: WorkoutSession) -> WorkoutSnapshot {
        WorkoutSnapshot(
            id: session.id,
            planSnapshot: session.planSnapshot,
            activities: session.activities,
            status: session.status,
            feedback: session.feedback,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            revision: session.revision
        )
    }

    private func makeTrainingRecord(_ session: WorkoutSession) throws -> TrainingRecord {
        guard session.status != .inProgress, let endedAt = session.endedAt else {
            throw TrainingApplicationError.workoutNotFinished
        }

        let activities = session.activities.map { performed -> TrainingRecordActivity in
            let plannedActivity = session.planSnapshot.projection.activities.first {
                $0.id == performed.plannedActivityID
            }
            let details: TrainingRecordActivityDetails
            switch performed.details {
            case let .strength(results):
                let plannedSets: [StrengthSetTarget]
                if case let .strength(plan)? = plannedActivity?.details {
                    plannedSets = plan.sets
                } else {
                    plannedSets = []
                }
                details = .strength(results.map { result in
                    let planned = plannedSets.first { $0.id == result.plannedSetID }
                    let deviates = result.status != .completed
                        || planned?.repetitions != result.actualRepetitions
                        || planned?.load != result.actualLoad
                        || planned?.rpe != result.actualRPE
                    return TrainingRecordStrengthSet(
                        id: result.id,
                        plannedSetID: result.plannedSetID,
                        plannedRepetitions: planned?.repetitions,
                        plannedLoad: planned?.load,
                        actualRepetitions: result.actualRepetitions,
                        actualLoad: result.actualLoad,
                        actualRPE: result.actualRPE,
                        status: result.status,
                        note: result.note,
                        hasDeviation: deviates
                    )
                })
            case let .cardio(results):
                let plannedSegments: [CardioSegmentTarget]
                if case let .cardio(plan)? = plannedActivity?.details {
                    plannedSegments = plan.segments
                } else {
                    plannedSegments = []
                }
                details = .cardio(results.map { result in
                    let planned = plannedSegments.first { $0.id == result.plannedSegmentID }
                    let deviates = result.status != .completed
                        || planned?.durationSeconds != result.actualDurationSeconds
                        || planned?.distance != result.actualDistance
                    return TrainingRecordCardioSegment(
                        id: result.id,
                        plannedSegmentID: result.plannedSegmentID,
                        plannedDurationSeconds: planned?.durationSeconds,
                        plannedDistance: planned?.distance,
                        actualDurationSeconds: result.actualDurationSeconds,
                        actualDistance: result.actualDistance,
                        status: result.status,
                        note: result.note,
                        hasDeviation: deviates
                    )
                })
            }
            return TrainingRecordActivity(
                id: performed.id,
                plannedActivityID: performed.plannedActivityID,
                order: performed.order,
                name: performed.name,
                details: details,
                note: performed.note
            )
        }

        return TrainingRecord(
            sessionID: session.id,
            title: session.planSnapshot.title,
            startedAt: session.startedAt,
            endedAt: endedAt,
            durationSeconds: max(0, Int(endedAt.timeIntervalSince(session.startedAt))),
            status: session.status,
            activities: activities,
            feedback: session.feedback
        )
    }

    private func mapRepositoryError(_ error: TrainingRepositoryError) -> TrainingApplicationError {
        switch error {
        case .activePlanAlreadyExists: .activePlanAlreadyExists
        case .planNotFound: .planNotFound
        case .planNotConfirmed: .planNotConfirmed
        case .activeWorkoutAlreadyExists: .activeWorkoutAlreadyExists
        case .workoutNotFound: .workoutNotFound
        case .staleRevision: .staleRevision
        case .idempotencyKeyConflict: .idempotencyKeyConflict
        case .unexpectedStoredResult: .persistenceFailure
        }
    }
}

private extension TrainingCommand {
    var idempotencyKey: UUID {
        switch self {
        case let .createDailyPlan(command): command.idempotencyKey
        case let .updateDailyPlan(command): command.idempotencyKey
        case let .startWorkout(command): command.idempotencyKey
        case let .recordStrengthSet(command): command.idempotencyKey
        case let .recordCardioSegment(command): command.idempotencyKey
        case let .completeWorkout(command): command.idempotencyKey
        }
    }

    var repositoryKind: RepositoryCommandKind {
        switch self {
        case .createDailyPlan: .createDailyPlan
        case .updateDailyPlan: .updateDailyPlan
        case .startWorkout: .startWorkout
        case .recordStrengthSet: .recordStrengthSet
        case .recordCardioSegment: .recordCardioSegment
        case .completeWorkout: .completeWorkout
        }
    }
}
