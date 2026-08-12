import Foundation

enum SegmentStatus: String, Codable, Sendable {
    case pending
    case completed
    case skipped
}

enum WorkoutStatus: String, Codable, Sendable {
    case inProgress
    case completed
    case partiallyCompleted
    case interrupted
}

enum PerceivedEffort: String, Codable, Sendable {
    case easy
    case moderate
    case hard
}

struct SubjectiveFeedback: Equatable, Codable, Sendable {
    let perceivedEffort: PerceivedEffort?
    let notes: String?
}

struct StrengthSetResult: Identifiable, Equatable, Sendable {
    let id: UUID
    let plannedSetID: UUID?
    fileprivate(set) var actualRepetitions: Int?
    fileprivate(set) var actualLoad: Load?
    fileprivate(set) var actualRPE: Double?
    fileprivate(set) var status: SegmentStatus
    fileprivate(set) var note: String?
}

struct CardioSegmentResult: Identifiable, Equatable, Sendable {
    let id: UUID
    let plannedSegmentID: UUID?
    fileprivate(set) var actualDurationSeconds: Int?
    fileprivate(set) var actualDistance: Distance?
    fileprivate(set) var status: SegmentStatus
    fileprivate(set) var note: String?
}

enum PerformedActivityDetails: Equatable, Sendable {
    case strength([StrengthSetResult])
    case cardio([CardioSegmentResult])
}

struct PerformedActivity: Identifiable, Equatable, Sendable {
    let id: UUID
    let plannedActivityID: UUID?
    let order: Int
    let name: String
    fileprivate(set) var details: PerformedActivityDetails
    fileprivate(set) var note: String?
}

/// Application 负责生成实际项目和训练段 ID，再把它们交给 Domain 建立稳定关联。
struct PerformedActivityIdentifiers: Equatable, Sendable {
    let activityID: UUID
    let segmentIDs: [UUID]
}

struct WorkoutSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let planSnapshot: PlanSnapshot
    private(set) var activities: [PerformedActivity]
    private(set) var status: WorkoutStatus
    private(set) var feedback: SubjectiveFeedback?
    let startedAt: Date
    private(set) var endedAt: Date?
    private(set) var revision: Int

    var sourcePlanID: UUID { planSnapshot.planID }
    var sourcePlanRevision: Int { planSnapshot.revision }

    static func start(
        id: UUID,
        plan: DailyPlan,
        identifiers: [PerformedActivityIdentifiers],
        startedAt: Date
    ) throws -> WorkoutSession {
        guard plan.status == .confirmed else {
            throw DomainError.planNotConfirmed
        }
        guard identifiers.count == plan.projection.activities.count else {
            throw DomainError.validation([.duplicateIdentifier])
        }
        let allIDs = identifiers.flatMap { [$0.activityID] + $0.segmentIDs }
        guard Set(allIDs).count == allIDs.count else {
            throw DomainError.validation([.duplicateIdentifier])
        }

        let performed = try zip(plan.projection.activities, identifiers).map { planned, ids in
            let details: PerformedActivityDetails
            switch planned.details {
            case let .strength(strength):
                guard ids.segmentIDs.count == strength.sets.count else {
                    throw DomainError.validation([.duplicateIdentifier])
                }
                details = .strength(zip(strength.sets, ids.segmentIDs).map { target, resultID in
                    StrengthSetResult(
                        id: resultID,
                        plannedSetID: target.id,
                        actualRepetitions: nil,
                        actualLoad: nil,
                        actualRPE: nil,
                        status: .pending,
                        note: nil
                    )
                })
            case let .cardio(cardio):
                guard ids.segmentIDs.count == cardio.segments.count else {
                    throw DomainError.validation([.duplicateIdentifier])
                }
                details = .cardio(zip(cardio.segments, ids.segmentIDs).map { target, resultID in
                    CardioSegmentResult(
                        id: resultID,
                        plannedSegmentID: target.id,
                        actualDurationSeconds: nil,
                        actualDistance: nil,
                        status: .pending,
                        note: nil
                    )
                })
            }

            return PerformedActivity(
                id: ids.activityID,
                plannedActivityID: planned.id,
                order: planned.order,
                name: planned.name,
                details: details,
                note: nil
            )
        }

        return WorkoutSession(
            id: id,
            planSnapshot: PlanSnapshot(
                planID: plan.id,
                revision: plan.revision,
                title: plan.title,
                document: plan.document,
                projection: plan.projection,
                capturedAt: startedAt
            ),
            activities: performed,
            status: .inProgress,
            feedback: nil,
            startedAt: startedAt,
            endedAt: nil,
            revision: 1
        )
    }

    /// 保存力量组实际值。`nil` 表示沿用快照中的计划值，显式的 0 则会原样保留。
    mutating func recordStrengthSet(
        id: UUID,
        actualRepetitions: Int?,
        actualLoad: Load?,
        actualRPE: Double?,
        note: String?
    ) throws {
        guard status == .inProgress else {
            throw DomainError.workoutAlreadyFinished
        }
        var issues: [ValidationIssue] = []
        if let actualRepetitions, actualRepetitions < 0 { issues.append(.negativeRepetitions) }
        if let actualLoad, actualLoad.value < 0 { issues.append(.negativeLoad) }
        if let actualRPE, actualRPE < 0 { issues.append(.negativeRPE) }
        guard issues.isEmpty else { throw DomainError.validation(issues) }
        guard let activityIndex = activities.firstIndex(where: { activity in
            guard case let .strength(sets) = activity.details else { return false }
            return sets.contains(where: { $0.id == id })
        }) else {
            throw DomainError.segmentNotFound
        }
        guard case var .strength(results) = activities[activityIndex].details,
              let resultIndex = results.firstIndex(where: { $0.id == id }),
              let plannedSetID = results[resultIndex].plannedSetID,
              let target = strengthTarget(id: plannedSetID) else {
            throw DomainError.segmentKindMismatch
        }

        results[resultIndex].actualRepetitions = actualRepetitions ?? target.repetitions
        results[resultIndex].actualLoad = actualLoad ?? target.load
        results[resultIndex].actualRPE = actualRPE ?? target.rpe
        results[resultIndex].status = .completed
        results[resultIndex].note = note
        activities[activityIndex].details = .strength(results)
        revision += 1
    }

    /// 保存有氧段实际值；是否达成目标与“是否完成了这一段”分开记录。
    mutating func recordCardioSegment(
        id: UUID,
        actualDurationSeconds: Int?,
        actualDistance: Distance?,
        note: String?
    ) throws {
        guard status == .inProgress else {
            throw DomainError.workoutAlreadyFinished
        }
        var issues: [ValidationIssue] = []
        if let actualDurationSeconds, actualDurationSeconds < 0 { issues.append(.negativeDuration) }
        if let actualDistance, actualDistance.value < 0 { issues.append(.negativeDistance) }
        guard issues.isEmpty else { throw DomainError.validation(issues) }

        guard let activityIndex = activities.firstIndex(where: { activity in
            guard case let .cardio(segments) = activity.details else { return false }
            return segments.contains(where: { $0.id == id })
        }) else {
            throw DomainError.segmentNotFound
        }
        guard case var .cardio(results) = activities[activityIndex].details,
              let resultIndex = results.firstIndex(where: { $0.id == id }),
              let plannedSegmentID = results[resultIndex].plannedSegmentID,
              let target = cardioTarget(id: plannedSegmentID) else {
            throw DomainError.segmentKindMismatch
        }

        results[resultIndex].actualDurationSeconds = actualDurationSeconds ?? target.durationSeconds
        results[resultIndex].actualDistance = actualDistance ?? target.distance
        results[resultIndex].status = .completed
        results[resultIndex].note = note
        activities[activityIndex].details = .cardio(results)
        revision += 1
    }

    /// 结束时把尚未完成的段固化为 `skipped`，避免历史 Session 保留可继续编辑的 pending 状态。
    mutating func finish(at endedAt: Date, feedback: SubjectiveFeedback?) throws {
        guard status == .inProgress else {
            throw DomainError.workoutAlreadyFinished
        }
        guard endedAt >= startedAt else {
            throw DomainError.finishBeforeStart
        }

        var completedCount = 0
        var totalCount = 0

        for activityIndex in activities.indices {
            switch activities[activityIndex].details {
            case var .strength(results):
                for resultIndex in results.indices {
                    totalCount += 1
                    if results[resultIndex].status == .completed {
                        completedCount += 1
                    } else {
                        results[resultIndex].status = .skipped
                    }
                }
                activities[activityIndex].details = .strength(results)
            case var .cardio(results):
                for resultIndex in results.indices {
                    totalCount += 1
                    if results[resultIndex].status == .completed {
                        completedCount += 1
                    } else {
                        results[resultIndex].status = .skipped
                    }
                }
                activities[activityIndex].details = .cardio(results)
            }
        }

        if completedCount == totalCount {
            status = .completed
        } else if completedCount > 0 {
            status = .partiallyCompleted
        } else {
            status = .interrupted
        }
        self.feedback = feedback
        self.endedAt = endedAt
        revision += 1
    }

    private func strengthTarget(id: UUID) -> StrengthSetTarget? {
        for activity in planSnapshot.projection.activities {
            guard case let .strength(plan) = activity.details else { continue }
            if let target = plan.sets.first(where: { $0.id == id }) {
                return target
            }
        }
        return nil
    }

    private func cardioTarget(id: UUID) -> CardioSegmentTarget? {
        for activity in planSnapshot.projection.activities {
            guard case let .cardio(plan) = activity.details else { continue }
            if let target = plan.segments.first(where: { $0.id == id }) {
                return target
            }
        }
        return nil
    }
}
