import Foundation
import SwiftData

/// SwiftData Entity 只属于 Infrastructure。领域模型保持纯 Swift，所有转换集中在 Mapper。
@Model
final class DailyPlanEntity {
    @Attribute(.unique) var id: UUID
    var scheduledDate: Date
    var title: String
    var rawDocument: String
    var notes: String?
    var statusRawValue: String
    var revision: Int
    var sourceRawValue: String
    var confirmedByUser: Bool
    var sourceReference: String?
    var createdAt: Date
    var updatedAt: Date
    /// 删除计划时连同项目和训练段删除；反向关系使 SwiftData 能维护所有权，避免留下孤儿段。
    @Relationship(deleteRule: .cascade, inverse: \PlannedActivityEntity.plan)
    var activities: [PlannedActivityEntity]
    /// 版本快照只属于所属计划，计划删除后不应在本地保留不可达的历史数据。
    @Relationship(deleteRule: .cascade, inverse: \PlanRevisionEntity.plan)
    var revisions: [PlanRevisionEntity]

    init(id: UUID, scheduledDate: Date, title: String, rawDocument: String, notes: String?, statusRawValue: String, revision: Int, sourceRawValue: String, confirmedByUser: Bool, sourceReference: String?, createdAt: Date, updatedAt: Date, activities: [PlannedActivityEntity] = [], revisions: [PlanRevisionEntity] = []) {
        self.id = id; self.scheduledDate = scheduledDate; self.title = title; self.rawDocument = rawDocument
        self.notes = notes; self.statusRawValue = statusRawValue; self.revision = revision
        self.sourceRawValue = sourceRawValue; self.confirmedByUser = confirmedByUser; self.sourceReference = sourceReference
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.activities = activities; self.revisions = revisions
    }
}

@Model
final class PlannedActivityEntity {
    @Attribute(.unique) var id: UUID
    var order: Int
    var name: String
    var notes: String?
    var kindRawValue: String
    var plan: DailyPlanEntity?
    /// 项目是其计划段的所有者；级联删除避免修改计划时遗留旧训练段。
    @Relationship(deleteRule: .cascade, inverse: \PlannedSegmentEntity.activity)
    var segments: [PlannedSegmentEntity]

    init(id: UUID, order: Int, name: String, notes: String?, kindRawValue: String, segments: [PlannedSegmentEntity] = []) {
        self.id = id; self.order = order; self.name = name; self.notes = notes; self.kindRawValue = kindRawValue; self.segments = segments
    }
}

@Model
final class PlannedSegmentEntity {
    @Attribute(.unique) var id: UUID
    var order: Int
    var repetitions: Int?
    var loadValue: String?
    var loadUnitRawValue: String?
    var durationSeconds: Int?
    var distanceValue: String?
    var distanceUnitRawValue: String?
    var targetHeartRateLower: Int?
    var targetHeartRateUpper: Int?
    /// RPE 没有被 Domain 限制为十分位，因此以十进制字符串无损保存。
    var targetRPEValue: String?
    var notes: String?
    var activity: PlannedActivityEntity?

    init(id: UUID, order: Int, repetitions: Int? = nil, loadValue: String? = nil, loadUnitRawValue: String? = nil, durationSeconds: Int? = nil, distanceValue: String? = nil, distanceUnitRawValue: String? = nil, targetHeartRateLower: Int? = nil, targetHeartRateUpper: Int? = nil, targetRPEValue: String? = nil, notes: String? = nil) {
        self.id = id; self.order = order; self.repetitions = repetitions; self.loadValue = loadValue; self.loadUnitRawValue = loadUnitRawValue
        self.durationSeconds = durationSeconds; self.distanceValue = distanceValue; self.distanceUnitRawValue = distanceUnitRawValue
        self.targetHeartRateLower = targetHeartRateLower; self.targetHeartRateUpper = targetHeartRateUpper; self.targetRPEValue = targetRPEValue; self.notes = notes
    }
}

@Model
final class PlanRevisionEntity {
    @Attribute(.unique) var id: UUID
    var revision: Int
    var snapshotData: Data
    var sourceRawValue: String
    var createdAt: Date
    var plan: DailyPlanEntity?

    init(id: UUID, revision: Int, snapshotData: Data, sourceRawValue: String, createdAt: Date) {
        self.id = id; self.revision = revision; self.snapshotData = snapshotData; self.sourceRawValue = sourceRawValue; self.createdAt = createdAt
    }
}

@Model
final class WorkoutSessionEntity {
    @Attribute(.unique) var id: UUID
    var sourcePlanID: UUID
    var sourcePlanRevision: Int
    var planSnapshotSchemaVersion: Int
    var planSnapshotData: Data
    /// 与规范化实际项目并存的恢复快照，保证关系迁移期间仍能原样重建训练聚合。
    var sessionData: Data
    var statusRawValue: String
    var startedAt: Date
    var endedAt: Date?
    var revision: Int
    var feedbackEffortRawValue: String?
    var feedbackNotes: String?
    /// Session 是实际项目的唯一所有者；结束或删除 Session 时同时清理实际训练段。
    @Relationship(deleteRule: .cascade, inverse: \PerformedActivityEntity.session)
    var activities: [PerformedActivityEntity]

    init(id: UUID, sourcePlanID: UUID, sourcePlanRevision: Int, planSnapshotSchemaVersion: Int, planSnapshotData: Data, sessionData: Data, statusRawValue: String, startedAt: Date, endedAt: Date?, revision: Int, feedbackEffortRawValue: String?, feedbackNotes: String?, activities: [PerformedActivityEntity] = []) {
        self.id = id; self.sourcePlanID = sourcePlanID; self.sourcePlanRevision = sourcePlanRevision
        self.planSnapshotSchemaVersion = planSnapshotSchemaVersion; self.planSnapshotData = planSnapshotData; self.sessionData = sessionData; self.statusRawValue = statusRawValue
        self.startedAt = startedAt; self.endedAt = endedAt; self.revision = revision; self.feedbackEffortRawValue = feedbackEffortRawValue; self.feedbackNotes = feedbackNotes; self.activities = activities
    }
}

@Model
final class PerformedActivityEntity {
    @Attribute(.unique) var id: UUID
    var plannedActivityID: UUID?
    var order: Int
    var name: String
    var notes: String?
    var kindRawValue: String
    var session: WorkoutSessionEntity?
    /// 实际项目删除时，其段也必须删除，防止历史查询读取到脱离 Session 的结果。
    @Relationship(deleteRule: .cascade, inverse: \PerformedSegmentEntity.activity)
    var segments: [PerformedSegmentEntity]

    init(id: UUID, plannedActivityID: UUID?, order: Int, name: String, notes: String?, kindRawValue: String, segments: [PerformedSegmentEntity] = []) {
        self.id = id; self.plannedActivityID = plannedActivityID; self.order = order; self.name = name; self.notes = notes; self.kindRawValue = kindRawValue; self.segments = segments
    }
}

@Model
final class PerformedSegmentEntity {
    @Attribute(.unique) var id: UUID
    var plannedSegmentID: UUID?
    var order: Int
    var statusRawValue: String
    var actualRepetitions: Int?
    var actualLoadValue: String?
    var actualLoadUnitRawValue: String?
    var actualDurationSeconds: Int?
    var actualDistanceValue: String?
    var actualDistanceUnitRawValue: String?
    /// 与计划 RPE 相同，采用无损字符串而不是假定十分位输入。
    var actualRPEValue: String?
    var notes: String?
    var activity: PerformedActivityEntity?

    init(id: UUID, plannedSegmentID: UUID?, order: Int, statusRawValue: String, actualRepetitions: Int? = nil, actualLoadValue: String? = nil, actualLoadUnitRawValue: String? = nil, actualDurationSeconds: Int? = nil, actualDistanceValue: String? = nil, actualDistanceUnitRawValue: String? = nil, actualRPEValue: String? = nil, notes: String? = nil) {
        self.id = id; self.plannedSegmentID = plannedSegmentID; self.order = order; self.statusRawValue = statusRawValue; self.actualRepetitions = actualRepetitions
        self.actualLoadValue = actualLoadValue; self.actualLoadUnitRawValue = actualLoadUnitRawValue; self.actualDurationSeconds = actualDurationSeconds
        self.actualDistanceValue = actualDistanceValue; self.actualDistanceUnitRawValue = actualDistanceUnitRawValue; self.actualRPEValue = actualRPEValue; self.notes = notes
    }
}

@Model
final class IdempotencyRecordEntity {
    @Attribute(.unique) var key: UUID
    var commandTypeRawValue: String
    var payload: Data
    var aggregateID: UUID
    var resultKindRawValue: String
    /// 写入完成时的不可变回执；重试绝不能读取后来发生的聚合状态。
    var resultData: Data
    var createdAt: Date

    init(key: UUID, commandTypeRawValue: String, payload: Data, aggregateID: UUID, resultKindRawValue: String, resultData: Data, createdAt: Date) {
        self.key = key; self.commandTypeRawValue = commandTypeRawValue; self.payload = payload; self.aggregateID = aggregateID; self.resultKindRawValue = resultKindRawValue; self.resultData = resultData; self.createdAt = createdAt
    }
}
