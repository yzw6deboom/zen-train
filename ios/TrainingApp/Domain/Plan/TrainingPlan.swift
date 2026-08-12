import Foundation

/// 原始计划表达始终保留；结构化失败时仍可保存为草稿。
struct PlanDocument: Equatable, Codable, Sendable {
    let rawText: String
    let notes: String?
}

enum PlanStatus: String, Codable, Sendable {
    case draft
    case confirmed
    case archived
}

/// 一组力量训练的计划目标；每一组都拥有独立 ID，实际结果将通过这个 ID 关联计划。
struct StrengthSetTarget: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let order: Int
    let repetitions: Int?
    let load: Load?
    let rpe: Double?
    let note: String?
}

/// 力量项目的逐组执行计划。
struct StrengthPlan: Equatable, Codable, Sendable {
    let sets: [StrengthSetTarget]

    /// 把界面的“统一设置”展开为逐组事实。
    ///
    /// ID 由 Application 注入，而不是由 View 或 Domain 随机生成；这让重试和测试都能保持确定性。
    static func expandingUniformTargets(
        setIDs: [UUID],
        repetitions: Int?,
        load: Load?,
        rpe: Double?,
        note: String?
    ) throws -> StrengthPlan {
        var issues: [ValidationIssue] = []
        if setIDs.isEmpty { issues.append(.emptyStrengthSets) }
        if Set(setIDs).count != setIDs.count { issues.append(.duplicateIdentifier) }
        if let repetitions, repetitions < 0 { issues.append(.negativeRepetitions) }
        if let load, load.value < 0 { issues.append(.negativeLoad) }
        if let rpe, rpe < 0 { issues.append(.negativeRPE) }
        guard issues.isEmpty else { throw DomainError.validation(issues) }

        return StrengthPlan(
            sets: setIDs.enumerated().map { order, id in
                StrengthSetTarget(
                    id: id,
                    order: order + 1,
                    repetitions: repetitions,
                    load: load,
                    rpe: rpe,
                    note: note
                )
            }
        )
    }
}

/// 有氧段当前至少支持时长；距离字段保留在 Domain 中，不要求阶段 B 提供界面。
struct CardioSegmentTarget: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let order: Int
    let durationSeconds: Int?
    let distance: Distance?
    let targetHeartRate: ClosedRange<Int>?
    let note: String?
}

struct CardioPlan: Equatable, Codable, Sendable {
    let segments: [CardioSegmentTarget]
}

enum PlannedActivityDetails: Equatable, Codable, Sendable {
    case strength(StrengthPlan)
    case cardio(CardioPlan)
}

struct PlannedActivity: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let order: Int
    let name: String
    let notes: String?
    let details: PlannedActivityDetails
}

struct ExecutionProjection: Equatable, Codable, Sendable {
    let activities: [PlannedActivity]
    let documentRevision: Int
}

/// 开始训练时固化的计划版本；后续实际结果只关联它，不修改它。
struct PlanSnapshot: Equatable, Codable, Sendable {
    let planID: UUID
    let revision: Int
    let title: String
    let document: PlanDocument
    let projection: ExecutionProjection
    let capturedAt: Date
}

/// 今日计划聚合只允许通过工厂和行为方法维护状态与 revision。
struct DailyPlan: Identifiable, Equatable, Sendable {
    let id: UUID
    private(set) var scheduledDate: Date
    private(set) var title: String
    private(set) var document: PlanDocument
    private(set) var projection: ExecutionProjection
    private(set) var status: PlanStatus
    private(set) var revision: Int
    private(set) var provenance: Provenance
    let createdAt: Date
    private(set) var updatedAt: Date

    static func create(
        id: UUID,
        scheduledDate: Date,
        title: String,
        document: PlanDocument,
        activities: [PlannedActivity],
        status: PlanStatus,
        provenance: Provenance,
        createdAt: Date
    ) throws -> DailyPlan {
        let issues = validationIssues(
            title: title,
            activities: activities,
            status: status,
            provenance: provenance
        )
        guard issues.isEmpty else {
            throw DomainError.validation(issues)
        }

        return DailyPlan(
            id: id,
            scheduledDate: scheduledDate,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            document: document,
            projection: ExecutionProjection(activities: activities, documentRevision: 1),
            status: status,
            revision: 1,
            provenance: provenance,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    /// 用完整的新计划内容替换当前版本；成功时 revision 只增加一次。
    mutating func revise(
        scheduledDate: Date,
        title: String,
        document: PlanDocument,
        activities: [PlannedActivity],
        status: PlanStatus,
        provenance: Provenance,
        updatedAt: Date
    ) throws {
        let issues = Self.validationIssues(
            title: title,
            activities: activities,
            status: status,
            provenance: provenance
        )
        guard issues.isEmpty else { throw DomainError.validation(issues) }

        let nextRevision = revision + 1
        self.scheduledDate = scheduledDate
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.document = document
        self.projection = ExecutionProjection(
            activities: activities,
            documentRevision: nextRevision
        )
        self.status = status
        self.revision = nextRevision
        self.provenance = provenance
        self.updatedAt = updatedAt
    }

    private static func validationIssues(
        title: String,
        activities: [PlannedActivity],
        status: PlanStatus,
        provenance: Provenance
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        func add(_ issue: ValidationIssue) {
            if !issues.contains(issue) { issues.append(issue) }
        }

        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(.emptyPlanTitle)
        }
        if status == .confirmed && activities.isEmpty {
            add(.missingExecutableActivity)
        }
        if status == .confirmed && !provenance.confirmedByUser {
            add(.confirmationRequired)
        }
        if Set(activities.map(\.id)).count != activities.count {
            add(.duplicateIdentifier)
        }
        if activities.map(\.order) != activities.indices.map({ $0 + 1 }) {
            add(.invalidActivityOrder)
        }

        for activity in activities {
            if activity.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                add(.emptyActivityName)
            }
            switch activity.details {
            case let .strength(plan):
                if plan.sets.isEmpty { add(.emptyStrengthSets) }
                if Set(plan.sets.map(\.id)).count != plan.sets.count {
                    add(.duplicateIdentifier)
                }
                if plan.sets.map(\.order) != plan.sets.indices.map({ $0 + 1 }) {
                    add(.invalidSegmentOrder)
                }
                for set in plan.sets {
                    if let repetitions = set.repetitions, repetitions < 0 {
                        add(.negativeRepetitions)
                    }
                    if let load = set.load, load.value < 0 { add(.negativeLoad) }
                    if let rpe = set.rpe, rpe < 0 { add(.negativeRPE) }
                }
            case let .cardio(plan):
                if plan.segments.isEmpty { add(.emptyCardioSegments) }
                if Set(plan.segments.map(\.id)).count != plan.segments.count {
                    add(.duplicateIdentifier)
                }
                if plan.segments.map(\.order) != plan.segments.indices.map({ $0 + 1 }) {
                    add(.invalidSegmentOrder)
                }
                for segment in plan.segments {
                    if let duration = segment.durationSeconds, duration < 0 {
                        add(.negativeDuration)
                    }
                    if let distance = segment.distance, distance.value < 0 {
                        add(.negativeDistance)
                    }
                }
            }
        }
        return issues
    }
}
