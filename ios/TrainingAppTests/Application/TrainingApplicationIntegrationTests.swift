import XCTest
@testable import TrainingApp

/// 通过最高公共 seam 验证真实 Application、Domain 与内存 Repository 的协作。
final class TrainingApplicationIntegrationTests: XCTestCase {
    @MainActor
    func testMixedWorkoutRoundTripKeepsPlanAndActualValuesSeparate() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let endedAt = Date(timeIntervalSince1970: 1_700_003_700)
        let repository = InMemoryTrainingRepository(calendar: calendar)
        let clock = ScriptedTrainingClock(values: [createdAt, startedAt, endedAt])
        let ids = ScriptedIDGenerator(
            values: (100...107).map(testUUID) + (200...207).map(testUUID)
        )
        let application: any TrainingApplication = DefaultTrainingApplication(
            repository: repository,
            clock: clock,
            idGenerator: ids
        )

        let create = CreateDailyPlanCommand(
            idempotencyKey: testUUID(900),
            source: .manual,
            scheduledDate: createdAt,
            title: "下肢与有氧",
            rawDocument: "深蹲 4 × 8 × 60kg；跑步机 20 分钟",
            notes: nil,
            activities: [
                PlannedActivityInput(
                    name: "深蹲",
                    notes: nil,
                    details: .strength(
                        .uniform(
                            setCount: 4,
                            target: StrengthSetTargetInput(
                                repetitions: 8,
                                load: Load(value: 60, unit: .kilogram),
                                rpe: nil,
                                note: nil
                            )
                        )
                    )
                ),
                PlannedActivityInput(
                    name: "跑步机",
                    notes: nil,
                    details: .cardio(
                        CardioPlanInput(
                            segments: [
                                CardioSegmentTargetInput(
                                    durationSeconds: 1_200,
                                    distance: nil,
                                    targetHeartRate: nil,
                                    note: nil
                                )
                            ]
                        )
                    )
                )
            ],
            confirmImmediately: true
        )

        let createMutation = try await application.execute(.createDailyPlan(create))
        guard case let .planSaved(plan) = createMutation else {
            return XCTFail("创建计划应返回 planSaved")
        }
        XCTAssertEqual(plan.id, testUUID(100))
        XCTAssertEqual(plan.status, .confirmed)
        XCTAssertEqual(plan.revision, 1)

        let start = StartWorkoutCommand(
            idempotencyKey: testUUID(901),
            source: .manual,
            planID: plan.id,
            expectedRevision: plan.revision
        )
        let startMutation = try await application.execute(.startWorkout(start))
        let replayedStart = try await application.execute(.startWorkout(start))
        XCTAssertEqual(replayedStart, startMutation)
        guard case var .workoutStarted(workout) = startMutation,
              case let .strength(strengthResults) = workout.activities[0].details,
              case let .cardio(cardioResults) = workout.activities[1].details else {
            return XCTFail("开始训练应生成力量和有氧的待记录结构")
        }
        XCTAssertEqual(workout.planSnapshot.capturedAt, startedAt)

        for (index, actualRepetitions) in [8, 8, 6, 8].enumerated() {
            let command = RecordStrengthSetCommand(
                idempotencyKey: testUUID(910 + index),
                source: .manual,
                sessionID: workout.id,
                expectedRevision: workout.revision,
                performedSetID: strengthResults[index].id,
                actualRepetitions: actualRepetitions,
                actualLoad: nil,
                actualRPE: nil,
                note: index == 2 ? "第三组少做两次" : nil
            )
            let mutation = try await application.execute(.recordStrengthSet(command))
            if index == 0 {
                let replayed = try await application.execute(.recordStrengthSet(command))
                XCTAssertEqual(replayed, mutation)
            }
            guard case let .workoutUpdated(updated) = mutation else {
                return XCTFail("记录力量组应返回 workoutUpdated")
            }
            workout = updated
        }

        let cardioCommand = RecordCardioSegmentCommand(
            idempotencyKey: testUUID(920),
            source: .manual,
            sessionID: workout.id,
            expectedRevision: workout.revision,
            performedSegmentID: cardioResults[0].id,
            actualDurationSeconds: 1_080,
            actualDistance: nil,
            note: "提前两分钟结束"
        )
        let cardioMutation = try await application.execute(.recordCardioSegment(cardioCommand))
        guard case let .workoutUpdated(updatedWorkout) = cardioMutation else {
            return XCTFail("记录有氧段应返回 workoutUpdated")
        }
        workout = updatedWorkout

        let complete = CompleteWorkoutCommand(
            idempotencyKey: testUUID(930),
            source: .manual,
            sessionID: workout.id,
            expectedRevision: workout.revision,
            feedback: SubjectiveFeedback(perceivedEffort: .hard, notes: "完成主要训练")
        )
        let completion = try await application.execute(.completeWorkout(complete))
        let replayedCompletion = try await application.execute(.completeWorkout(complete))
        XCTAssertEqual(completion, replayedCompletion)
        guard case let .workoutCompleted(sessionID) = completion else {
            return XCTFail("完成训练应返回可查询记录的 Session ID")
        }

        let record = try await application.record(sessionID: sessionID)
        XCTAssertEqual(record.status, .completed)
        XCTAssertEqual(record.endedAt, endedAt)
        guard case let .strength(recordedSets) = record.activities[0].details,
              case let .cardio(recordedCardio) = record.activities[1].details else {
            return XCTFail("训练记录应保留力量和有氧明细")
        }
        XCTAssertEqual(recordedSets[2].plannedRepetitions, 8)
        XCTAssertEqual(recordedSets[2].actualRepetitions, 6)
        XCTAssertTrue(recordedSets[2].hasDeviation)
        XCTAssertEqual(recordedCardio[0].plannedDurationSeconds, 1_200)
        XCTAssertEqual(recordedCardio[0].actualDurationSeconds, 1_080)
        XCTAssertTrue(recordedCardio[0].hasDeviation)

        let activeWorkout = try await application.activeWorkout()
        XCTAssertNil(activeWorkout)
        let today = try await application.today(on: createdAt)
        guard case let .completed(todayRecord) = today.state else {
            return XCTFail("完成后 TodaySnapshot 应进入 completed")
        }
        XCTAssertEqual(todayRecord.sessionID, sessionID)
    }

    @MainActor
    func testConfirmedEmptyPlanIsRejectedButRawDraftCanBeSaved() async throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let application = makeApplication(
            clockValues: [createdAt, createdAt],
            idValues: [testUUID(300), testUUID(301)]
        )
        let confirmed = CreateDailyPlanCommand(
            idempotencyKey: testUUID(940),
            source: .manual,
            scheduledDate: createdAt,
            title: "今日训练",
            rawDocument: "稍后再补项目",
            notes: nil,
            activities: [],
            confirmImmediately: true
        )

        do {
            _ = try await application.execute(.createDailyPlan(confirmed))
            XCTFail("空计划不应被确认")
        } catch let error as TrainingApplicationError {
            XCTAssertEqual(error, .invalidPlan([.missingExecutableActivity]))
        }

        let draft = CreateDailyPlanCommand(
            idempotencyKey: testUUID(941),
            source: .manual,
            scheduledDate: createdAt,
            title: "今日训练",
            rawDocument: "稍后再补项目",
            notes: nil,
            activities: [],
            confirmImmediately: false
        )
        let mutation = try await application.execute(.createDailyPlan(draft))
        guard case let .planSaved(snapshot) = mutation else {
            return XCTFail("原文草稿应可保存")
        }
        XCTAssertEqual(snapshot.status, .draft)
        XCTAssertEqual(snapshot.document.rawText, "稍后再补项目")

        do {
            _ = try await application.execute(
                .startWorkout(
                    StartWorkoutCommand(
                        idempotencyKey: testUUID(942),
                        source: .manual,
                        planID: snapshot.id,
                        expectedRevision: snapshot.revision
                    )
                )
            )
            XCTFail("草稿计划不应开始训练")
        } catch let error as TrainingApplicationError {
            XCTAssertEqual(error, .planNotConfirmed)
        }
    }

    @MainActor
    func testSameDaySecondPlanAndStaleUpdateAreRejected() async throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let repository = InMemoryTrainingRepository(calendar: utcCalendar())
        let application: any TrainingApplication = DefaultTrainingApplication(
            repository: repository,
            clock: ScriptedTrainingClock(values: [createdAt, createdAt, updatedAt]),
            idGenerator: ScriptedIDGenerator(values: (400...420).map(testUUID))
        )
        let first = try await createSimpleConfirmedPlan(
            application: application,
            key: testUUID(950),
            date: createdAt
        )

        do {
            _ = try await createSimpleConfirmedPlan(
                application: application,
                key: testUUID(951),
                date: createdAt.addingTimeInterval(3_600)
            )
            XCTFail("同一天不应静默创建第二个未归档计划")
        } catch let error as TrainingApplicationError {
            XCTAssertEqual(error, .activePlanAlreadyExists)
        }

        let originalActivity = first.activities[0]
        let update = UpdateDailyPlanCommand(
            idempotencyKey: testUUID(952),
            source: .manual,
            planID: first.id,
            expectedRevision: first.revision,
            scheduledDate: createdAt,
            title: "更新后的计划",
            rawDocument: "深蹲 1 组",
            notes: nil,
            activities: [input(from: originalActivity)],
            confirmImmediately: true
        )
        let mutation = try await application.execute(.updateDailyPlan(update))
        guard case let .planSaved(updated) = mutation else {
            return XCTFail("更新计划应返回 planSaved")
        }
        XCTAssertEqual(updated.revision, 2)

        let stale = UpdateDailyPlanCommand(
            idempotencyKey: testUUID(953),
            source: .manual,
            planID: first.id,
            expectedRevision: first.revision,
            scheduledDate: createdAt,
            title: "过期覆盖",
            rawDocument: "过期版本",
            notes: nil,
            activities: [input(from: originalActivity)],
            confirmImmediately: true
        )
        do {
            _ = try await application.execute(.updateDailyPlan(stale))
            XCTFail("过期 revision 不应覆盖新计划")
        } catch let error as TrainingApplicationError {
            XCTAssertEqual(error, .staleRevision)
        }
    }

    @MainActor
    func testConcurrentStartsProduceOneSessionAndIdempotencyKeyRejectsDifferentPayload() async throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let repository = InMemoryTrainingRepository(calendar: utcCalendar())
        let application: any TrainingApplication = DefaultTrainingApplication(
            repository: repository,
            clock: ScriptedTrainingClock(values: [createdAt, createdAt, createdAt]),
            idGenerator: ScriptedIDGenerator(values: (500...540).map(testUUID))
        )
        let plan = try await createSimpleConfirmedPlan(
            application: application,
            key: testUUID(960),
            date: createdAt
        )
        let first = StartWorkoutCommand(
            idempotencyKey: testUUID(961),
            source: .manual,
            planID: plan.id,
            expectedRevision: plan.revision
        )
        let second = StartWorkoutCommand(
            idempotencyKey: testUUID(962),
            source: .manual,
            planID: plan.id,
            expectedRevision: plan.revision
        )

        let results = await withTaskGroup(of: Result<TrainingMutation, Error>.self) { group in
            group.addTask {
                do { return .success(try await application.execute(.startWorkout(first))) }
                catch { return .failure(error) }
            }
            group.addTask {
                do { return .success(try await application.execute(.startWorkout(second))) }
                catch { return .failure(error) }
            }
            var collected: [Result<TrainingMutation, Error>] = []
            for await result in group { collected.append(result) }
            return collected
        }
        let successCount = results.filter { result in
            if case .success = result { return true }
            return false
        }.count
        XCTAssertEqual(successCount, 1)
        let failures: [TrainingApplicationError] = results.compactMap { result in
            guard case let .failure(error) = result else { return nil }
            return error as? TrainingApplicationError
        }
        XCTAssertEqual(failures, [TrainingApplicationError.activeWorkoutAlreadyExists])
        let activeWorkout = try await application.activeWorkout()
        XCTAssertNotNil(activeWorkout)

        let conflictingCreate = CreateDailyPlanCommand(
            idempotencyKey: testUUID(960),
            source: .manual,
            scheduledDate: createdAt,
            title: "复用同一个 key 的不同内容",
            rawDocument: "冲突",
            notes: nil,
            activities: [],
            confirmImmediately: false
        )
        do {
            _ = try await application.execute(.createDailyPlan(conflictingCreate))
            XCTFail("同一幂等 key 不应接受不同 payload")
        } catch let error as TrainingApplicationError {
            XCTAssertEqual(error, .idempotencyKeyConflict)
        }
    }

    @MainActor
    func testIdempotentCreateReplaysFromRepositoryAfterApplicationIsRebuilt() async throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let repository = InMemoryTrainingRepository(calendar: utcCalendar())
        let firstApplication: any TrainingApplication = DefaultTrainingApplication(
            repository: repository,
            clock: ScriptedTrainingClock(values: [createdAt]),
            idGenerator: ScriptedIDGenerator(values: (600...602).map(testUUID))
        )
        let command = simpleConfirmedPlanCommand(key: testUUID(970), date: createdAt)
        let first = try await firstApplication.execute(.createDailyPlan(command))

        // 第二个 Application 没有可用时间或 ID；若重试错误地重走业务链路，测试会立即失败。
        let rebuiltApplication: any TrainingApplication = DefaultTrainingApplication(
            repository: repository,
            clock: ScriptedTrainingClock(values: []),
            idGenerator: ScriptedIDGenerator(values: [])
        )
        let replayed = try await rebuiltApplication.execute(.createDailyPlan(command))

        XCTAssertEqual(replayed, first)
        let day = await repository.loadDay(on: createdAt)
        XCTAssertEqual(day.plans.count, 1)
    }

    @MainActor
    func testManualAndConfirmedAgentCommandsUseTheSameDomainRules() async throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let manualApplication = makeApplication(
            clockValues: [createdAt],
            idValues: (700...702).map(testUUID)
        )
        let agentApplication = makeApplication(
            clockValues: [createdAt],
            idValues: (700...702).map(testUUID)
        )
        let manualCommand = simpleConfirmedPlanCommand(
            key: testUUID(980),
            date: createdAt,
            source: .manual
        )
        let agentCommand = simpleConfirmedPlanCommand(
            key: testUUID(981),
            date: createdAt,
            source: .agent
        )

        let manualMutation = try await manualApplication.execute(.createDailyPlan(manualCommand))
        let agentMutation = try await agentApplication.execute(.createDailyPlan(agentCommand))
        guard case let .planSaved(manual) = manualMutation,
              case let .planSaved(agent) = agentMutation else {
            return XCTFail("两种来源都应进入相同的计划保存结果")
        }
        XCTAssertEqual(manual.activities, agent.activities)
        XCTAssertEqual(manual.status, agent.status)
        XCTAssertEqual(manual.revision, agent.revision)
        XCTAssertEqual(manual.provenance.source, .manual)
        XCTAssertEqual(agent.provenance.source, .agent)
        XCTAssertTrue(agent.provenance.confirmedByUser)
    }

    @MainActor
    func testPerSetStrengthTargetsPreserveDifferentValues() async throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let application = makeApplication(
            clockValues: [createdAt],
            idValues: (800...804).map(testUUID)
        )
        let command = CreateDailyPlanCommand(
            idempotencyKey: testUUID(990),
            source: .manual,
            scheduledDate: createdAt,
            title: "递增力量训练",
            rawDocument: "40kg × 10；50kg × 8；60kg × 6",
            notes: nil,
            activities: [
                PlannedActivityInput(
                    name: "深蹲",
                    notes: nil,
                    details: .strength(
                        .perSet([
                            StrengthSetTargetInput(
                                repetitions: 10,
                                load: Load(value: 40, unit: .kilogram),
                                rpe: nil,
                                note: nil
                            ),
                            StrengthSetTargetInput(
                                repetitions: 8,
                                load: Load(value: 50, unit: .kilogram),
                                rpe: nil,
                                note: nil
                            ),
                            StrengthSetTargetInput(
                                repetitions: 6,
                                load: Load(value: 60, unit: .kilogram),
                                rpe: nil,
                                note: nil
                            )
                        ])
                    )
                )
            ],
            confirmImmediately: true
        )

        let mutation = try await application.execute(.createDailyPlan(command))
        guard case let .planSaved(plan) = mutation,
              case let .strength(strength) = plan.activities[0].details else {
            return XCTFail("逐组输入应保存为力量计划")
        }
        XCTAssertEqual(strength.sets.map(\.order), [1, 2, 3])
        XCTAssertEqual(strength.sets.map(\.repetitions), [10, 8, 6])
        XCTAssertEqual(strength.sets.map { $0.load?.value }, [40, 50, 60])
    }

    @MainActor
    private func makeApplication(
        clockValues: [Date],
        idValues: [UUID]
    ) -> any TrainingApplication {
        DefaultTrainingApplication(
            repository: InMemoryTrainingRepository(calendar: utcCalendar()),
            clock: ScriptedTrainingClock(values: clockValues),
            idGenerator: ScriptedIDGenerator(values: idValues)
        )
    }

    @MainActor
    private func createSimpleConfirmedPlan(
        application: any TrainingApplication,
        key: UUID,
        date: Date
    ) async throws -> PlanEditorSnapshot {
        let command = simpleConfirmedPlanCommand(key: key, date: date)
        let mutation = try await application.execute(.createDailyPlan(command))
        guard case let .planSaved(plan) = mutation else {
            throw TrainingApplicationError.persistenceFailure
        }
        return plan
    }

    @MainActor
    private func simpleConfirmedPlanCommand(
        key: UUID,
        date: Date,
        source: OperationSource = .manual
    ) -> CreateDailyPlanCommand {
        CreateDailyPlanCommand(
            idempotencyKey: key,
            source: source,
            scheduledDate: date,
            title: "力量训练",
            rawDocument: "深蹲 1 × 8 × 60kg",
            notes: nil,
            activities: [
                PlannedActivityInput(
                    name: "深蹲",
                    notes: nil,
                    details: .strength(
                        .uniform(
                            setCount: 1,
                            target: StrengthSetTargetInput(
                                repetitions: 8,
                                load: Load(value: 60, unit: .kilogram),
                                rpe: nil,
                                note: nil
                            )
                        )
                    )
                )
            ],
            confirmImmediately: true
        )
    }

    @MainActor
    private func input(from activity: PlannedActivity) -> PlannedActivityInput {
        let details: PlannedActivityDetailsInput
        switch activity.details {
        case let .strength(plan):
            details = .strength(
                .perSet(
                    plan.sets.map {
                        StrengthSetTargetInput(
                            id: $0.id,
                            repetitions: $0.repetitions,
                            load: $0.load,
                            rpe: $0.rpe,
                            note: $0.note
                        )
                    }
                )
            )
        case let .cardio(plan):
            details = .cardio(
                CardioPlanInput(
                    segments: plan.segments.map {
                        CardioSegmentTargetInput(
                            id: $0.id,
                            durationSeconds: $0.durationSeconds,
                            distance: $0.distance,
                            targetHeartRate: $0.targetHeartRate,
                            note: $0.note
                        )
                    }
                )
            )
        }
        return PlannedActivityInput(
            id: activity.id,
            name: activity.name,
            notes: activity.notes,
            details: details
        )
    }

    @MainActor
    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

}

private func testUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
}

/// 测试时间边界的替身；actor 让可变队列满足 Swift 6 的并发安全要求。
private actor ScriptedTrainingClock: TrainingClock {
    private var values: [Date]

    init(values: [Date]) {
        self.values = values
    }

    func now() -> Date {
        precondition(!values.isEmpty, "测试时钟的时间已用完")
        return values.removeFirst()
    }
}

/// ID 同样属于系统边界，测试用固定序列保证聚合关联和失败信息稳定。
private actor ScriptedIDGenerator: IDGenerator {
    private var values: [UUID]

    init(values: [UUID]) {
        self.values = values
    }

    func next() -> UUID {
        precondition(!values.isEmpty, "测试 ID 序列已用完")
        return values.removeFirst()
    }
}
