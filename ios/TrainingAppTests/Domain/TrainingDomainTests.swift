import XCTest
@testable import TrainingApp

/// 从纯 Swift Domain 的公共行为验证阶段 B 业务规则。
final class TrainingDomainTests: XCTestCase {
    /// “统一设置”只是输入便利；进入 Domain 后，每组必须拥有独立身份和同一份目标值。
    func testUniformStrengthTargetsExpandIntoIndependentSets() throws {
        let setIDs = [uuid(1), uuid(2), uuid(3), uuid(4)]
        let load = Load(value: 60, unit: .kilogram)

        let plan = try StrengthPlan.expandingUniformTargets(
            setIDs: setIDs,
            repetitions: 8,
            load: load,
            rpe: nil,
            note: nil
        )

        XCTAssertEqual(plan.sets.map(\.id), setIDs)
        XCTAssertEqual(plan.sets.map(\.order), [1, 2, 3, 4])
        XCTAssertEqual(plan.sets.map(\.repetitions), [8, 8, 8, 8])
        XCTAssertEqual(plan.sets.map(\.load), [load, load, load, load])
    }

    /// 草稿可以暂时没有结构化项目，但确认后的计划必须真正可执行。
    func testConfirmedPlanRequiresAtLeastOneExecutableActivity() {
        XCTAssertThrowsError(
            try DailyPlan.create(
                id: uuid(10),
                scheduledDate: Date(timeIntervalSince1970: 1_700_000_000),
                title: "今日训练",
                document: PlanDocument(rawText: "", notes: nil),
                activities: [],
                status: .confirmed,
                provenance: Provenance(source: .manual, confirmedByUser: true, sourceReference: nil),
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .validation([.missingExecutableActivity])
            )
        }
    }

    /// 实际次数可以偏离计划，但计划快照必须继续保存开始训练时的 8 次目标。
    func testRecordingActualStrengthSetDoesNotChangePlanSnapshot() throws {
        let plan = try makeConfirmedStrengthPlan()
        var session = try WorkoutSession.start(
            id: uuid(30),
            plan: plan,
            identifiers: [
                PerformedActivityIdentifiers(activityID: uuid(31), segmentIDs: [uuid(32)])
            ],
            startedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        try session.recordStrengthSet(
            id: uuid(32),
            actualRepetitions: 6,
            actualLoad: Load(value: 60, unit: .kilogram),
            actualRPE: nil,
            note: "最后两次力竭"
        )

        guard case let .strength(planDetails) = session.planSnapshot.projection.activities[0].details,
              case let .strength(results) = session.activities[0].details else {
            return XCTFail("预期得到力量计划与力量实际结果")
        }

        XCTAssertEqual(planDetails.sets[0].repetitions, 8)
        XCTAssertEqual(results[0].actualRepetitions, 6)
        XCTAssertEqual(results[0].plannedSetID, planDetails.sets[0].id)
        XCTAssertEqual(results[0].status, .completed)
        XCTAssertEqual(session.revision, 2)
    }

    /// 完成一部分训练段后结束，应把剩余段固化为 skipped，并得到部分完成终态。
    func testFinishingWithCompletedAndPendingSegmentsProducesPartialCompletion() throws {
        let strength = try StrengthPlan.expandingUniformTargets(
            setIDs: [uuid(41), uuid(42)],
            repetitions: 8,
            load: Load(value: 60, unit: .kilogram),
            rpe: nil,
            note: nil
        )
        let plan = try makeConfirmedPlan(details: .strength(strength))
        var session = try WorkoutSession.start(
            id: uuid(50),
            plan: plan,
            identifiers: [
                PerformedActivityIdentifiers(activityID: uuid(51), segmentIDs: [uuid(52), uuid(53)])
            ],
            startedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        try session.recordStrengthSet(
            id: uuid(52),
            actualRepetitions: nil,
            actualLoad: nil,
            actualRPE: nil,
            note: nil
        )

        try session.finish(
            at: Date(timeIntervalSince1970: 1_700_000_700),
            feedback: SubjectiveFeedback(perceivedEffort: .hard, notes: "最后一组未做")
        )

        guard case let .strength(results) = session.activities[0].details else {
            return XCTFail("预期得到力量训练结果")
        }
        XCTAssertEqual(results.map(\.status), [.completed, .skipped])
        XCTAssertEqual(session.status, .partiallyCompleted)
        XCTAssertEqual(session.endedAt, Date(timeIntervalSince1970: 1_700_000_700))
        XCTAssertEqual(session.revision, 3)

        XCTAssertThrowsError(
            try session.recordStrengthSet(
                id: uuid(53),
                actualRepetitions: 8,
                actualLoad: nil,
                actualRPE: nil,
                note: nil
            )
        ) { error in
            XCTAssertEqual(error as? DomainError, .workoutAlreadyFinished)
        }
    }

    /// 所有训练段完成时得到 completed；没有任何完成项时得到 interrupted。
    func testFinishCalculatesCompletedAndInterruptedTerminalStates() throws {
        let strength = try StrengthPlan.expandingUniformTargets(
            setIDs: [uuid(61)],
            repetitions: 8,
            load: Load(value: 60, unit: .kilogram),
            rpe: nil,
            note: nil
        )
        let plan = try makeConfirmedPlan(details: .strength(strength))
        let identifiers = [
            PerformedActivityIdentifiers(activityID: uuid(62), segmentIDs: [uuid(63)])
        ]
        var completed = try WorkoutSession.start(
            id: uuid(64),
            plan: plan,
            identifiers: identifiers,
            startedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        try completed.recordStrengthSet(
            id: uuid(63),
            actualRepetitions: nil,
            actualLoad: nil,
            actualRPE: nil,
            note: nil
        )
        try completed.finish(
            at: Date(timeIntervalSince1970: 1_700_000_200),
            feedback: nil
        )
        XCTAssertEqual(completed.status, .completed)

        var interrupted = try WorkoutSession.start(
            id: uuid(65),
            plan: plan,
            identifiers: [
                PerformedActivityIdentifiers(activityID: uuid(66), segmentIDs: [uuid(67)])
            ],
            startedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        try interrupted.finish(
            at: Date(timeIntervalSince1970: 1_700_000_200),
            feedback: nil
        )
        XCTAssertEqual(interrupted.status, .interrupted)
    }

    /// 负数不是有效训练目标；0 次和 0 重量仍是可表达的显式值。
    func testStrengthTargetValidationRejectsNegativeValuesAndKeepsZero() throws {
        XCTAssertThrowsError(
            try StrengthPlan.expandingUniformTargets(
                setIDs: [uuid(70)],
                repetitions: -1,
                load: Load(value: -1, unit: .kilogram),
                rpe: nil,
                note: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .validation([.negativeRepetitions, .negativeLoad])
            )
        }

        let zero = try StrengthPlan.expandingUniformTargets(
            setIDs: [uuid(71)],
            repetitions: 0,
            load: Load(value: 0, unit: .kilogram),
            rpe: nil,
            note: nil
        )
        XCTAssertEqual(zero.sets[0].repetitions, 0)
        XCTAssertEqual(zero.sets[0].load?.value, 0)
    }

    /// 用可读的固定 UUID 让失败信息稳定，测试不会依赖随机值。
    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    private func makeConfirmedStrengthPlan() throws -> DailyPlan {
        let strength = try StrengthPlan.expandingUniformTargets(
            setIDs: [uuid(21)],
            repetitions: 8,
            load: Load(value: 60, unit: .kilogram),
            rpe: nil,
            note: nil
        )
        return try makeConfirmedPlan(details: .strength(strength))
    }

    private func makeConfirmedPlan(details: PlannedActivityDetails) throws -> DailyPlan {
        try DailyPlan.create(
            id: uuid(10),
            scheduledDate: Date(timeIntervalSince1970: 1_700_000_000),
            title: "下肢训练",
            document: PlanDocument(rawText: "深蹲 1 组", notes: nil),
            activities: [
                PlannedActivity(
                    id: uuid(20),
                    order: 1,
                    name: "深蹲",
                    notes: nil,
                    details: details
                )
            ],
            status: .confirmed,
            provenance: Provenance(source: .manual, confirmedByUser: true, sourceReference: nil),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
