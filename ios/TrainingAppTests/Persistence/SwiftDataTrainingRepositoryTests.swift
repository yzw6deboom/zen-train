import SwiftData
import XCTest
@testable import TrainingApp

/// 阶段 C 只通过 Repository seam 验证 SwiftData：上层无需知道 Entity 或 ModelContext 的存在。
final class SwiftDataTrainingRepositoryTests: XCTestCase {
    @MainActor
    func testRebuiltRepositoryRestoresPlanSessionActualValuesAndIdempotencyReceipt() async throws {
        let container = try TrainingModelContainer.make(isStoredInMemoryOnly: true)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = try makePlan(date: date)
        let createRequest = IdempotencyRequest(
            key: identifier(10), commandKind: .createDailyPlan, payload: Data([1])
        )
        let firstRepository = SwiftDataTrainingRepository(modelContainer: container, calendar: utcCalendar())
        _ = try await firstRepository.createPlan(plan, idempotency: createRequest)

        let startedSession = try WorkoutSession.start(
            id: identifier(20),
            plan: plan,
            identifiers: [PerformedActivityIdentifiers(
                activityID: identifier(21), segmentIDs: [identifier(22)]
            )],
            startedAt: date.addingTimeInterval(60)
        )
        let startRequest = IdempotencyRequest(
            key: identifier(11), commandKind: .startWorkout, payload: Data([2])
        )
        _ = try await firstRepository.startSession(
            startedSession, expectedPlanRevision: plan.revision, idempotency: startRequest
        )
        var recordedSession = startedSession
        try recordedSession.recordStrengthSet(
            id: identifier(22),
            actualRepetitions: 6,
            actualLoad: Load(value: 135, unit: .pound),
            actualRPE: 8.25,
            note: "计划之外的实际结果"
        )
        let recordRequest = IdempotencyRequest(
            key: identifier(12), commandKind: .recordStrengthSet, payload: Data([3])
        )
        _ = try await firstRepository.updateSession(
            recordedSession, expectedRevision: startedSession.revision, idempotency: recordRequest
        )

        // 使用同一个 Container 重建 Adapter，模拟 App/Service 重建后从 SwiftData 恢复。
        let rebuiltRepository = SwiftDataTrainingRepository(modelContainer: container, calendar: utcCalendar())
        let restoredPlan = try await rebuiltRepository.loadPlan(id: plan.id)
        let restoredSession = try await rebuiltRepository.loadSession(id: recordedSession.id)
        let replayedCreate = try await rebuiltRepository.replay(createRequest)
        let replayedStart = try await rebuiltRepository.replay(startRequest)
        let replayedRecord = try await rebuiltRepository.replay(recordRequest)
        XCTAssertEqual(restoredPlan, plan)
        XCTAssertEqual(restoredSession, recordedSession)
        XCTAssertEqual(replayedCreate, .plan(plan))
        XCTAssertEqual(replayedStart, .session(startedSession))
        XCTAssertEqual(replayedRecord, .session(recordedSession))

        let day = try await rebuiltRepository.loadDay(on: date)
        XCTAssertEqual(day.plans, [plan])
        XCTAssertEqual(day.activeSession, recordedSession)
    }

    @MainActor
    func testRepositoryEnforcesRevisionAndSingleActiveWorkoutAfterPersistence() async throws {
        let container = try TrainingModelContainer.make(isStoredInMemoryOnly: true)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = try makePlan(date: date)
        let repository = SwiftDataTrainingRepository(modelContainer: container, calendar: utcCalendar())
        _ = try await repository.createPlan(
            plan,
            idempotency: IdempotencyRequest(key: identifier(30), commandKind: .createDailyPlan, payload: Data([1]))
        )

        var revisedPlan = plan
        try revisedPlan.revise(
            scheduledDate: date,
            title: "更新后的深蹲",
            document: PlanDocument(rawText: "深蹲", notes: nil),
            activities: plan.projection.activities,
            status: .confirmed,
            provenance: plan.provenance,
            updatedAt: date.addingTimeInterval(10)
        )
        do {
            _ = try await repository.updatePlan(
                revisedPlan,
                expectedRevision: 0,
                idempotency: IdempotencyRequest(key: identifier(31), commandKind: .updateDailyPlan, payload: Data([2]))
            )
            XCTFail("过期 revision 不应覆盖持久化计划")
        } catch let error as TrainingRepositoryError {
            XCTAssertEqual(error, .staleRevision)
        }

        _ = try await repository.updatePlan(
            revisedPlan,
            expectedRevision: plan.revision,
            idempotency: IdempotencyRequest(key: identifier(34), commandKind: .updateDailyPlan, payload: Data([5]))
        )
        let originalRevision = try await repository.loadPlanRevision(planID: plan.id, revision: 1)
        let updatedRevision = try await repository.loadPlanRevision(planID: plan.id, revision: 2)
        XCTAssertEqual(originalRevision, plan)
        XCTAssertEqual(updatedRevision, revisedPlan)

        let session = try WorkoutSession.start(
            id: identifier(40), plan: revisedPlan,
            identifiers: [PerformedActivityIdentifiers(activityID: identifier(41), segmentIDs: [identifier(42)])],
            startedAt: date.addingTimeInterval(60)
        )
        _ = try await repository.startSession(
            session,
            expectedPlanRevision: revisedPlan.revision,
            idempotency: IdempotencyRequest(key: identifier(32), commandKind: .startWorkout, payload: Data([3]))
        )
        let anotherSession = try WorkoutSession.start(
            id: identifier(43), plan: revisedPlan,
            identifiers: [PerformedActivityIdentifiers(activityID: identifier(44), segmentIDs: [identifier(45)])],
            startedAt: date.addingTimeInterval(61)
        )
        do {
            _ = try await repository.startSession(
                anotherSession,
                expectedPlanRevision: revisedPlan.revision,
                idempotency: IdempotencyRequest(key: identifier(33), commandKind: .startWorkout, payload: Data([4]))
            )
            XCTFail("同一时间不应保存第二个进行中的训练")
        } catch let error as TrainingRepositoryError {
            XCTAssertEqual(error, .activeWorkoutAlreadyExists)
        }
    }

    private func makePlan(date: Date) throws -> DailyPlan {
        try DailyPlan.create(
            id: identifier(1), scheduledDate: date, title: "深蹲",
            document: PlanDocument(rawText: "深蹲 8 次 60kg", notes: "保留原文"),
            activities: [PlannedActivity(
                id: identifier(2), order: 1, name: "深蹲", notes: "主项",
                details: .strength(StrengthPlan(sets: [StrengthSetTarget(
                    id: identifier(3), order: 1, repetitions: 8,
                    load: Load(value: 60, unit: .kilogram), rpe: 7.55, note: "控制动作"
                )]))
            )],
            status: .confirmed,
            provenance: Provenance(source: .manual, confirmedByUser: true, sourceReference: nil),
            createdAt: date
        )
    }

    private func identifier(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
