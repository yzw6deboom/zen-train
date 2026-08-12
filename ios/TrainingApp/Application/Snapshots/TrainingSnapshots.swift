import Foundation

/// 计划编辑与待开始页面使用的只读状态。
struct PlanEditorSnapshot: Equatable, Sendable {
    let id: UUID
    let scheduledDate: Date
    let title: String
    let document: PlanDocument
    let activities: [PlannedActivity]
    let status: PlanStatus
    let revision: Int
    let provenance: Provenance
}

/// 训练页面使用的只读状态；计划快照与实际结果仍是两个独立字段。
struct WorkoutSnapshot: Equatable, Sendable {
    let id: UUID
    let planSnapshot: PlanSnapshot
    let activities: [PerformedActivity]
    let status: WorkoutStatus
    let feedback: SubjectiveFeedback?
    let startedAt: Date
    let endedAt: Date?
    let revision: Int
}

struct TrainingRecordStrengthSet: Identifiable, Equatable, Sendable {
    let id: UUID
    let plannedSetID: UUID?
    let plannedRepetitions: Int?
    let plannedLoad: Load?
    let actualRepetitions: Int?
    let actualLoad: Load?
    let actualRPE: Double?
    let status: SegmentStatus
    let note: String?
    let hasDeviation: Bool
}

struct TrainingRecordCardioSegment: Identifiable, Equatable, Sendable {
    let id: UUID
    let plannedSegmentID: UUID?
    let plannedDurationSeconds: Int?
    let plannedDistance: Distance?
    let actualDurationSeconds: Int?
    let actualDistance: Distance?
    let status: SegmentStatus
    let note: String?
    let hasDeviation: Bool
}

enum TrainingRecordActivityDetails: Equatable, Sendable {
    case strength([TrainingRecordStrengthSet])
    case cardio([TrainingRecordCardioSegment])
}

struct TrainingRecordActivity: Identifiable, Equatable, Sendable {
    let id: UUID
    let plannedActivityID: UUID?
    let order: Int
    let name: String
    let details: TrainingRecordActivityDetails
    let note: String?
}

/// 已结束 Session 的只读投影，不会产生另一份可写训练事实。
struct TrainingRecord: Equatable, Sendable {
    let sessionID: UUID
    let title: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let status: WorkoutStatus
    let activities: [TrainingRecordActivity]
    let feedback: SubjectiveFeedback?
}

struct TrainingRecordSummary: Equatable, Sendable {
    let sessionID: UUID
    let title: String
    let endedAt: Date
    let status: WorkoutStatus
}

enum TodayState: Equatable, Sendable {
    case noPlan
    case draft(PlanEditorSnapshot)
    case ready(PlanEditorSnapshot)
    case workoutInProgress(WorkoutSnapshot)
    case completed(TrainingRecord)
}

struct TodaySnapshot: Equatable, Sendable {
    let state: TodayState
    let recentRecords: [TrainingRecordSummary]
}
