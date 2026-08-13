import Foundation

enum TrainingPersistenceError: Error, Sendable {
    case invalidStoredData
    case unsupportedSnapshotVersion
}

/// 让每一个 Decimal 都以十进制字符串落库，避免浮点近似污染训练重量和距离。
enum SwiftDataTrainingMapper {
    static let snapshotSchemaVersion = 1

    static func makePlanEntity(_ plan: DailyPlan) throws -> DailyPlanEntity {
        let entity = DailyPlanEntity(
            id: plan.id, scheduledDate: plan.scheduledDate, title: plan.title,
            rawDocument: plan.document.rawText, notes: plan.document.notes,
            statusRawValue: plan.status.rawValue, revision: plan.revision,
            sourceRawValue: plan.provenance.source.rawValue,
            confirmedByUser: plan.provenance.confirmedByUser,
            sourceReference: plan.provenance.sourceReference,
            createdAt: plan.createdAt, updatedAt: plan.updatedAt
        )
        entity.activities = try plan.projection.activities.map(makePlannedActivityEntity)
        entity.revisions = [try makeRevisionEntity(plan)]
        return entity
    }

    static func update(_ entity: DailyPlanEntity, from plan: DailyPlan) throws {
        entity.scheduledDate = plan.scheduledDate; entity.title = plan.title; entity.rawDocument = plan.document.rawText; entity.notes = plan.document.notes
        entity.statusRawValue = plan.status.rawValue; entity.revision = plan.revision; entity.sourceRawValue = plan.provenance.source.rawValue
        entity.confirmedByUser = plan.provenance.confirmedByUser; entity.sourceReference = plan.provenance.sourceReference; entity.updatedAt = plan.updatedAt
        entity.activities = try plan.projection.activities.map(makePlannedActivityEntity)
        entity.revisions.append(try makeRevisionEntity(plan))
    }

    static func makePlan(from entity: DailyPlanEntity) throws -> DailyPlan {
        guard let status = PlanStatus(rawValue: entity.statusRawValue), let source = OperationSource(rawValue: entity.sourceRawValue) else { throw TrainingPersistenceError.invalidStoredData }
        let activities = try entity.activities.sorted { $0.order < $1.order }.map(makePlannedActivity)
        return try DailyPlan.restore(
            id: entity.id, scheduledDate: entity.scheduledDate, title: entity.title,
            document: PlanDocument(rawText: entity.rawDocument, notes: entity.notes),
            projection: ExecutionProjection(activities: activities, documentRevision: entity.revision), status: status,
            revision: entity.revision,
            provenance: Provenance(source: source, confirmedByUser: entity.confirmedByUser, sourceReference: entity.sourceReference),
            createdAt: entity.createdAt, updatedAt: entity.updatedAt
        )
    }

    static func makePlan(fromRevisionData data: Data) throws -> DailyPlan {
        let stored = try JSONDecoder().decode(PersistedPlanRevision.self, from: data)
        return try stored.makePlan()
    }

    static func encode(_ plan: DailyPlan) throws -> Data {
        try JSONEncoder().encode(PersistedPlanRevision(plan: plan))
    }

    static func makeSessionEntity(_ session: WorkoutSession) throws -> WorkoutSessionEntity {
        let snapshot = try JSONEncoder().encode(session.planSnapshot)
        let entity = WorkoutSessionEntity(
            id: session.id, sourcePlanID: session.sourcePlanID, sourcePlanRevision: session.sourcePlanRevision,
            planSnapshotSchemaVersion: snapshotSchemaVersion, planSnapshotData: snapshot, sessionData: try encode(session), statusRawValue: session.status.rawValue,
            startedAt: session.startedAt, endedAt: session.endedAt, revision: session.revision,
            feedbackEffortRawValue: session.feedback?.perceivedEffort?.rawValue, feedbackNotes: session.feedback?.notes
        )
        entity.activities = try session.activities.map(makePerformedActivityEntity)
        return entity
    }

    static func update(_ entity: WorkoutSessionEntity, from session: WorkoutSession) throws {
        entity.sourcePlanID = session.sourcePlanID; entity.sourcePlanRevision = session.sourcePlanRevision
        entity.planSnapshotSchemaVersion = snapshotSchemaVersion; entity.planSnapshotData = try JSONEncoder().encode(session.planSnapshot); entity.sessionData = try encode(session)
        entity.statusRawValue = session.status.rawValue; entity.startedAt = session.startedAt; entity.endedAt = session.endedAt; entity.revision = session.revision
        entity.feedbackEffortRawValue = session.feedback?.perceivedEffort?.rawValue; entity.feedbackNotes = session.feedback?.notes
        entity.activities = try session.activities.map(makePerformedActivityEntity)
    }

    static func makeSession(from entity: WorkoutSessionEntity) throws -> WorkoutSession {
        guard entity.planSnapshotSchemaVersion == snapshotSchemaVersion else { throw TrainingPersistenceError.unsupportedSnapshotVersion }
        return try decodeSession(entity.sessionData)
    }

    static func encode(_ session: WorkoutSession) throws -> Data {
        try JSONEncoder().encode(PersistedWorkoutSession(session: session))
    }

    static func decodeSession(_ data: Data) throws -> WorkoutSession {
        try JSONDecoder().decode(PersistedWorkoutSession.self, from: data).makeSession()
    }

    private static func makePlannedActivityEntity(_ activity: PlannedActivity) throws -> PlannedActivityEntity {
        switch activity.details {
        case let .strength(plan):
            let entity = PlannedActivityEntity(id: activity.id, order: activity.order, name: activity.name, notes: activity.notes, kindRawValue: "strength")
            entity.segments = plan.sets.map { target in PlannedSegmentEntity(id: target.id, order: target.order, repetitions: target.repetitions, loadValue: target.load.map(decimalString), loadUnitRawValue: target.load?.unit.rawValue, targetRPEValue: target.rpe.map(doubleString), notes: target.note) }
            return entity
        case let .cardio(plan):
            let entity = PlannedActivityEntity(id: activity.id, order: activity.order, name: activity.name, notes: activity.notes, kindRawValue: "cardio")
            entity.segments = plan.segments.map { target in PlannedSegmentEntity(id: target.id, order: target.order, durationSeconds: target.durationSeconds, distanceValue: target.distance.map(decimalString), distanceUnitRawValue: target.distance?.unit.rawValue, targetHeartRateLower: target.targetHeartRate?.lowerBound, targetHeartRateUpper: target.targetHeartRate?.upperBound, notes: target.note) }
            return entity
        }
    }

    private static func makePlannedActivity(from entity: PlannedActivityEntity) throws -> PlannedActivity {
        switch entity.kindRawValue {
        case "strength":
            return PlannedActivity(id: entity.id, order: entity.order, name: entity.name, notes: entity.notes, details: .strength(StrengthPlan(sets: try entity.segments.sorted { $0.order < $1.order }.map { segment in StrengthSetTarget(id: segment.id, order: segment.order, repetitions: segment.repetitions, load: try load(value: segment.loadValue, unit: segment.loadUnitRawValue), rpe: try double(segment.targetRPEValue), note: segment.notes) })))
        case "cardio":
            return PlannedActivity(id: entity.id, order: entity.order, name: entity.name, notes: entity.notes, details: .cardio(CardioPlan(segments: try entity.segments.sorted { $0.order < $1.order }.map { segment in CardioSegmentTarget(id: segment.id, order: segment.order, durationSeconds: segment.durationSeconds, distance: try distance(value: segment.distanceValue, unit: segment.distanceUnitRawValue), targetHeartRate: try heartRate(lower: segment.targetHeartRateLower, upper: segment.targetHeartRateUpper), note: segment.notes) })))
        default: throw TrainingPersistenceError.invalidStoredData
        }
    }

    private static func makePerformedActivityEntity(_ activity: PerformedActivity) throws -> PerformedActivityEntity {
        switch activity.details {
        case let .strength(results):
            let entity = PerformedActivityEntity(id: activity.id, plannedActivityID: activity.plannedActivityID, order: activity.order, name: activity.name, notes: activity.note, kindRawValue: "strength")
            entity.segments = results.enumerated().map { index, result in PerformedSegmentEntity(id: result.id, plannedSegmentID: result.plannedSetID, order: index + 1, statusRawValue: result.status.rawValue, actualRepetitions: result.actualRepetitions, actualLoadValue: result.actualLoad.map(decimalString), actualLoadUnitRawValue: result.actualLoad?.unit.rawValue, actualRPEValue: result.actualRPE.map(doubleString), notes: result.note) }
            return entity
        case let .cardio(results):
            let entity = PerformedActivityEntity(id: activity.id, plannedActivityID: activity.plannedActivityID, order: activity.order, name: activity.name, notes: activity.note, kindRawValue: "cardio")
            entity.segments = results.enumerated().map { index, result in PerformedSegmentEntity(id: result.id, plannedSegmentID: result.plannedSegmentID, order: index + 1, statusRawValue: result.status.rawValue, actualDurationSeconds: result.actualDurationSeconds, actualDistanceValue: result.actualDistance.map(decimalString), actualDistanceUnitRawValue: result.actualDistance?.unit.rawValue, notes: result.note) }
            return entity
        }
    }

    private static func makePerformedActivity(from entity: PerformedActivityEntity) throws -> PerformedActivity {
        switch entity.kindRawValue {
        case "strength":
            return PerformedActivity(id: entity.id, plannedActivityID: entity.plannedActivityID, order: entity.order, name: entity.name, details: .strength(try entity.segments.sorted { $0.order < $1.order }.map { segment in StrengthSetResult(id: segment.id, plannedSetID: segment.plannedSegmentID, actualRepetitions: segment.actualRepetitions, actualLoad: try load(value: segment.actualLoadValue, unit: segment.actualLoadUnitRawValue), actualRPE: try double(segment.actualRPEValue), status: try segmentStatus(segment.statusRawValue), note: segment.notes) }), note: entity.notes)
        case "cardio":
            return PerformedActivity(id: entity.id, plannedActivityID: entity.plannedActivityID, order: entity.order, name: entity.name, details: .cardio(try entity.segments.sorted { $0.order < $1.order }.map { segment in CardioSegmentResult(id: segment.id, plannedSegmentID: segment.plannedSegmentID, actualDurationSeconds: segment.actualDurationSeconds, actualDistance: try distance(value: segment.actualDistanceValue, unit: segment.actualDistanceUnitRawValue), status: try segmentStatus(segment.statusRawValue), note: segment.notes) }), note: entity.notes)
        default: throw TrainingPersistenceError.invalidStoredData
        }
    }

    private static func makeRevisionEntity(_ plan: DailyPlan) throws -> PlanRevisionEntity {
        return PlanRevisionEntity(id: UUID(), revision: plan.revision, snapshotData: try encode(plan), sourceRawValue: plan.provenance.source.rawValue, createdAt: plan.updatedAt)
    }

    private static func makeFeedback(effort: String?, notes: String?) throws -> SubjectiveFeedback? {
        guard effort != nil || notes != nil else { return nil }
        guard let effort else { return SubjectiveFeedback(perceivedEffort: nil, notes: notes) }
        guard let value = PerceivedEffort(rawValue: effort) else { throw TrainingPersistenceError.invalidStoredData }
        return SubjectiveFeedback(perceivedEffort: value, notes: notes)
    }

    private static func decimalString(_ load: Load) -> String { NSDecimalNumber(decimal: load.value).stringValue }
    private static func decimalString(_ distance: Distance) -> String { NSDecimalNumber(decimal: distance.value).stringValue }
    private static func doubleString(_ value: Double) -> String { String(value) }
    private static func double(_ value: String?) throws -> Double? { guard let value else { return nil }; guard let parsed = Double(value) else { throw TrainingPersistenceError.invalidStoredData }; return parsed }
    private static func load(value: String?, unit: String?) throws -> Load? { guard value != nil || unit != nil else { return nil }; guard let value, let decimal = Decimal(string: value), let unit, let parsed = LoadUnit(rawValue: unit) else { throw TrainingPersistenceError.invalidStoredData }; return Load(value: decimal, unit: parsed) }
    private static func distance(value: String?, unit: String?) throws -> Distance? { guard value != nil || unit != nil else { return nil }; guard let value, let decimal = Decimal(string: value), let unit, let parsed = DistanceUnit(rawValue: unit) else { throw TrainingPersistenceError.invalidStoredData }; return Distance(value: decimal, unit: parsed) }
    private static func heartRate(lower: Int?, upper: Int?) throws -> ClosedRange<Int>? { guard lower != nil || upper != nil else { return nil }; guard let lower, let upper, lower <= upper else { throw TrainingPersistenceError.invalidStoredData }; return lower...upper }
    private static func segmentStatus(_ value: String) throws -> SegmentStatus { guard let status = SegmentStatus(rawValue: value) else { throw TrainingPersistenceError.invalidStoredData }; return status }
}

private struct PersistedPlanRevision: Codable {
    let id: UUID; let scheduledDate: Date; let title: String; let document: PlanDocument; let projection: ExecutionProjection; let status: PlanStatus; let revision: Int; let provenance: Provenance; let createdAt: Date; let updatedAt: Date
    init(plan: DailyPlan) { id = plan.id; scheduledDate = plan.scheduledDate; title = plan.title; document = plan.document; projection = plan.projection; status = plan.status; revision = plan.revision; provenance = plan.provenance; createdAt = plan.createdAt; updatedAt = plan.updatedAt }
    func makePlan() throws -> DailyPlan { try DailyPlan.restore(id: id, scheduledDate: scheduledDate, title: title, document: document, projection: projection, status: status, revision: revision, provenance: provenance, createdAt: createdAt, updatedAt: updatedAt) }
}

private struct PersistedWorkoutSession: Codable {
    let id: UUID; let planSnapshot: PlanSnapshot; let activities: [PersistedPerformedActivity]; let status: WorkoutStatus; let feedback: SubjectiveFeedback?; let startedAt: Date; let endedAt: Date?; let revision: Int
    init(session: WorkoutSession) { id = session.id; planSnapshot = session.planSnapshot; activities = session.activities.map(PersistedPerformedActivity.init); status = session.status; feedback = session.feedback; startedAt = session.startedAt; endedAt = session.endedAt; revision = session.revision }
    func makeSession() throws -> WorkoutSession { WorkoutSession.restore(id: id, planSnapshot: planSnapshot, activities: try activities.map { try $0.makeActivity() }, status: status, feedback: feedback, startedAt: startedAt, endedAt: endedAt, revision: revision) }
}

private struct PersistedPerformedActivity: Codable {
    let id: UUID; let plannedActivityID: UUID?; let order: Int; let name: String; let note: String?; let kind: String; let strength: [PersistedStrengthResult]?; let cardio: [PersistedCardioResult]?
    init(_ activity: PerformedActivity) { id = activity.id; plannedActivityID = activity.plannedActivityID; order = activity.order; name = activity.name; note = activity.note; switch activity.details { case let .strength(results): kind = "strength"; strength = results.map(PersistedStrengthResult.init); cardio = nil; case let .cardio(results): kind = "cardio"; strength = nil; cardio = results.map(PersistedCardioResult.init) } }
    func makeActivity() throws -> PerformedActivity { switch kind { case "strength": guard let strength else { throw TrainingPersistenceError.invalidStoredData }; return PerformedActivity(id: id, plannedActivityID: plannedActivityID, order: order, name: name, details: .strength(strength.map { $0.makeResult() }), note: note); case "cardio": guard let cardio else { throw TrainingPersistenceError.invalidStoredData }; return PerformedActivity(id: id, plannedActivityID: plannedActivityID, order: order, name: name, details: .cardio(cardio.map { $0.makeResult() }), note: note); default: throw TrainingPersistenceError.invalidStoredData } }
}

private struct PersistedStrengthResult: Codable {
    let id: UUID; let plannedSetID: UUID?; let actualRepetitions: Int?; let actualLoad: Load?; let actualRPE: Double?; let status: SegmentStatus; let note: String?
    init(_ value: StrengthSetResult) { id = value.id; plannedSetID = value.plannedSetID; actualRepetitions = value.actualRepetitions; actualLoad = value.actualLoad; actualRPE = value.actualRPE; status = value.status; note = value.note }
    func makeResult() -> StrengthSetResult { StrengthSetResult(id: id, plannedSetID: plannedSetID, actualRepetitions: actualRepetitions, actualLoad: actualLoad, actualRPE: actualRPE, status: status, note: note) }
}

private struct PersistedCardioResult: Codable {
    let id: UUID; let plannedSegmentID: UUID?; let actualDurationSeconds: Int?; let actualDistance: Distance?; let status: SegmentStatus; let note: String?
    init(_ value: CardioSegmentResult) { id = value.id; plannedSegmentID = value.plannedSegmentID; actualDurationSeconds = value.actualDurationSeconds; actualDistance = value.actualDistance; status = value.status; note = value.note }
    func makeResult() -> CardioSegmentResult { CardioSegmentResult(id: id, plannedSegmentID: plannedSegmentID, actualDurationSeconds: actualDurationSeconds, actualDistance: actualDistance, status: status, note: note) }
}
