import Foundation

struct StrengthSetTargetInput: Equatable, Codable, Sendable {
    let id: UUID?
    let repetitions: Int?
    let load: Load?
    let rpe: Double?
    let note: String?

    init(
        id: UUID? = nil,
        repetitions: Int?,
        load: Load?,
        rpe: Double?,
        note: String?
    ) {
        self.id = id
        self.repetitions = repetitions
        self.load = load
        self.rpe = rpe
        self.note = note
    }
}

enum StrengthPlanInput: Equatable, Codable, Sendable {
    case uniform(setCount: Int, target: StrengthSetTargetInput)
    case perSet([StrengthSetTargetInput])
}

struct CardioSegmentTargetInput: Equatable, Codable, Sendable {
    let id: UUID?
    let durationSeconds: Int?
    let distance: Distance?
    let targetHeartRate: ClosedRange<Int>?
    let note: String?

    init(
        id: UUID? = nil,
        durationSeconds: Int?,
        distance: Distance?,
        targetHeartRate: ClosedRange<Int>?,
        note: String?
    ) {
        self.id = id
        self.durationSeconds = durationSeconds
        self.distance = distance
        self.targetHeartRate = targetHeartRate
        self.note = note
    }
}

struct CardioPlanInput: Equatable, Codable, Sendable {
    let segments: [CardioSegmentTargetInput]
}

enum PlannedActivityDetailsInput: Equatable, Codable, Sendable {
    case strength(StrengthPlanInput)
    case cardio(CardioPlanInput)
}

struct PlannedActivityInput: Equatable, Codable, Sendable {
    let id: UUID?
    let name: String
    let notes: String?
    let details: PlannedActivityDetailsInput

    init(
        id: UUID? = nil,
        name: String,
        notes: String?,
        details: PlannedActivityDetailsInput
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.details = details
    }
}

struct CreateDailyPlanCommand: Equatable, Codable, Sendable {
    let idempotencyKey: UUID
    let source: OperationSource
    let scheduledDate: Date
    let title: String
    let rawDocument: String
    let notes: String?
    let activities: [PlannedActivityInput]
    let confirmImmediately: Bool
}

struct UpdateDailyPlanCommand: Equatable, Codable, Sendable {
    let idempotencyKey: UUID
    let source: OperationSource
    let planID: UUID
    let expectedRevision: Int
    let scheduledDate: Date
    let title: String
    let rawDocument: String
    let notes: String?
    let activities: [PlannedActivityInput]
    let confirmImmediately: Bool
}

struct StartWorkoutCommand: Equatable, Codable, Sendable {
    let idempotencyKey: UUID
    let source: OperationSource
    let planID: UUID
    let expectedRevision: Int
}

struct RecordStrengthSetCommand: Equatable, Codable, Sendable {
    let idempotencyKey: UUID
    let source: OperationSource
    let sessionID: UUID
    let expectedRevision: Int
    let performedSetID: UUID
    let actualRepetitions: Int?
    let actualLoad: Load?
    let actualRPE: Double?
    let note: String?
}

struct RecordCardioSegmentCommand: Equatable, Codable, Sendable {
    let idempotencyKey: UUID
    let source: OperationSource
    let sessionID: UUID
    let expectedRevision: Int
    let performedSegmentID: UUID
    let actualDurationSeconds: Int?
    let actualDistance: Distance?
    let note: String?
}

struct CompleteWorkoutCommand: Equatable, Codable, Sendable {
    let idempotencyKey: UUID
    let source: OperationSource
    let sessionID: UUID
    let expectedRevision: Int
    let feedback: SubjectiveFeedback?
}

enum TrainingCommand: Equatable, Codable, Sendable {
    case createDailyPlan(CreateDailyPlanCommand)
    case updateDailyPlan(UpdateDailyPlanCommand)
    case startWorkout(StartWorkoutCommand)
    case recordStrengthSet(RecordStrengthSetCommand)
    case recordCardioSegment(RecordCardioSegmentCommand)
    case completeWorkout(CompleteWorkoutCommand)
}
