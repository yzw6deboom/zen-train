import Observation
import SwiftUI

/// 阶段 D 的组合根：它只负责在四个 Feature 之间选择当前应展示的页面。
///
/// 所有持久化和领域规则仍位于 `TrainingApplication` 之后；这里的状态仅是页面状态。
struct AppRootView: View {
    let environment: AppEnvironment

    @State private var todayFeature: TodayFeatureModel

    init(environment: AppEnvironment, trainingApplication: any TrainingApplication) {
        self.environment = environment
        _todayFeature = State(initialValue: TodayFeatureModel(application: trainingApplication))
    }

    var body: some View {
        Group {
            if let snapshot = todayFeature.snapshot {
                content(for: snapshot)
            } else {
                ProgressView("正在准备今天的训练")
            }
        }
        .tint(TrainingAppearance.action)
        .task { await todayFeature.load() }
        .alert("暂时无法完成操作", isPresented: errorBinding) {
            Button("知道了", role: .cancel) { todayFeature.errorMessage = nil }
        } message: {
            Text(todayFeature.errorMessage ?? "请稍后重试。")
        }
        .sheet(isPresented: $todayFeature.isPresentingPlanEditor, onDismiss: {
            Task { await todayFeature.load() }
        }) {
            PlanEditorFeatureView(
                application: todayFeature.application,
                existingPlan: todayFeature.editingPlan
            )
        }
    }

    @ViewBuilder
    private func content(for snapshot: TodaySnapshot) -> some View {
        switch snapshot.state {
        case .noPlan:
            TodayFeatureView(
                environment: environment,
                snapshot: snapshot,
                onCreatePlan: { todayFeature.presentNewPlan() },
                onEditPlan: { _ in },
                onStartWorkout: { _ in }
            )
        case .draft, .ready:
            TodayFeatureView(
                environment: environment,
                snapshot: snapshot,
                onCreatePlan: { todayFeature.presentNewPlan() },
                onEditPlan: { todayFeature.presentEditPlan($0) },
                onStartWorkout: { plan in
                    Task { await todayFeature.startWorkout(plan: plan) }
                }
            )
        case let .workoutInProgress(workout):
            WorkoutFeatureView(
                application: todayFeature.application,
                initialSnapshot: workout,
                onWorkoutFinished: { await todayFeature.load() }
            )
        case let .completed(record):
            TrainingRecordFeatureView(record: record, onRefresh: { Task { await todayFeature.load() } })
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { todayFeature.errorMessage != nil },
            set: { if !$0 { todayFeature.errorMessage = nil } }
        )
    }
}

// MARK: - Today Feature

@MainActor
@Observable
final class TodayFeatureModel {
    let application: any TrainingApplication
    private(set) var snapshot: TodaySnapshot?
    var isPresentingPlanEditor = false
    private(set) var editingPlan: PlanEditorSnapshot?
    var errorMessage: String?

    init(application: any TrainingApplication) {
        self.application = application
    }

    func load() async {
        do {
            snapshot = try await application.today(on: Calendar.current.startOfDay(for: .now))
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func presentNewPlan() {
        editingPlan = nil
        isPresentingPlanEditor = true
    }

    func presentEditPlan(_ plan: PlanEditorSnapshot) {
        editingPlan = plan
        isPresentingPlanEditor = true
    }

    func startWorkout(plan: PlanEditorSnapshot) async {
        do {
            _ = try await application.execute(.startWorkout(StartWorkoutCommand(
                idempotencyKey: UUID(),
                source: .manual,
                planID: plan.id,
                expectedRevision: plan.revision
            )))
            await load()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}

private struct TodayFeatureView: View {
    let environment: AppEnvironment
    let snapshot: TodaySnapshot
    let onCreatePlan: () -> Void
    let onEditPlan: (PlanEditorSnapshot) -> Void
    let onStartWorkout: (PlanEditorSnapshot) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("今天")
                            .font(.largeTitle.bold())
                        Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                            .foregroundStyle(.secondary)
                    }

                    stateCard

                    if !snapshot.recentRecords.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("最近训练")
                                .font(.headline)
                            ForEach(snapshot.recentRecords, id: \.sessionID) { record in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    VStack(alignment: .leading) {
                                        Text(record.title)
                                        Text(record.endedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(record.status.displayName)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(.background, in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(environment.displayName)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var stateCard: some View {
        switch snapshot.state {
        case .noPlan:
            EmptyTodayCard(onCreatePlan: onCreatePlan)
        case let .draft(plan):
            PlanReadyCard(plan: plan, isDraft: true, onEdit: { onEditPlan(plan) }, onStart: { onStartWorkout(plan) })
        case let .ready(plan):
            PlanReadyCard(plan: plan, isDraft: false, onEdit: { onEditPlan(plan) }, onStart: { onStartWorkout(plan) })
        case .workoutInProgress, .completed:
            EmptyView()
        }
    }
}

private struct EmptyTodayCard: View {
    let onCreatePlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(TrainingAppearance.action)
            Text("给今天留一点训练时间")
                .font(.title2.bold())
            Text("从一个简单计划开始。完成后，实际表现会被完整保留。")
                .foregroundStyle(.secondary)
            Button("创建今日计划", action: onCreatePlan)
                .buttonStyle(.borderedProminent)
                .tint(TrainingAppearance.action)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(TrainingAppearance.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct PlanReadyCard: View {
    let plan: PlanEditorSnapshot
    let isDraft: Bool
    let onEdit: () -> Void
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(isDraft ? "草稿" : "已准备", systemImage: isDraft ? "pencil" : "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isDraft ? .orange : .green)
                Spacer()
                Text("\(plan.activities.count) 个项目")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(plan.title)
                .font(.title2.bold())
            if !plan.activities.isEmpty {
                Text(plan.activities.map(\.name).joined(separator: " · "))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                Button("编辑", action: onEdit)
                    .buttonStyle(.bordered)
                Button(isDraft ? "完善计划" : "开始训练", action: isDraft ? onEdit : onStart)
                .buttonStyle(.borderedProminent)
                .tint(TrainingAppearance.action)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(TrainingAppearance.card, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Plan Editor Feature

@MainActor
@Observable
final class PlanEditorFeatureModel {
    private let application: any TrainingApplication
    private let existingPlan: PlanEditorSnapshot?
    var title: String
    var notes: String
    fileprivate var activities: [ActivityDraft]
    var isSaving = false
    var errorMessage: String?

    init(application: any TrainingApplication, existingPlan: PlanEditorSnapshot?) {
        self.application = application
        self.existingPlan = existingPlan
        title = existingPlan?.title ?? ""
        notes = existingPlan?.document.notes ?? ""
        activities = existingPlan?.activities.map(ActivityDraft.init) ?? []
    }

    func save() async -> Bool {
        isSaving = true
        defer { isSaving = false }

        let inputs = activities.map(\.commandInput)
        do {
            if let existingPlan {
                _ = try await application.execute(.updateDailyPlan(UpdateDailyPlanCommand(
                    idempotencyKey: UUID(), source: .manual, planID: existingPlan.id,
                    expectedRevision: existingPlan.revision, scheduledDate: Calendar.current.startOfDay(for: .now),
                    title: title, rawDocument: notes, notes: notes.isEmpty ? nil : notes,
                    activities: inputs, confirmImmediately: true
                )))
            } else {
                _ = try await application.execute(.createDailyPlan(CreateDailyPlanCommand(
                    idempotencyKey: UUID(), source: .manual,
                    scheduledDate: Calendar.current.startOfDay(for: .now), title: title,
                    rawDocument: notes, notes: notes.isEmpty ? nil : notes,
                    activities: inputs, confirmImmediately: true
                )))
            }
            return true
        } catch {
            errorMessage = UserFacingError.message(for: error)
            return false
        }
    }
}

private struct PlanEditorFeatureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlanEditorFeatureModel
    @State private var isAddingActivity = false

    init(application: any TrainingApplication, existingPlan: PlanEditorSnapshot?) {
        _model = State(initialValue: PlanEditorFeatureModel(
            application: application,
            existingPlan: existingPlan
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("今天练什么") {
                    TextField("计划名称，例如：下肢力量", text: $model.title)
                    TextField("备注（可选）", text: $model.notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    ForEach(model.activities) { activity in
                        HStack(spacing: 12) {
                            Image(systemName: activity.kind.symbolName)
                                .foregroundStyle(TrainingAppearance.action)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(activity.name)
                                Text(activity.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { model.activities.remove(atOffsets: $0) }

                    Button {
                        isAddingActivity = true
                    } label: {
                        Label("添加训练项目", systemImage: "plus")
                    }
                } header: {
                    Text("训练项目")
                } footer: {
                    Text("力量项目会按每一组保存目标；有氧项目目前记录时长。")
                }
            }
            .navigationTitle("创建今日计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isSaving ? "保存中" : "保存") {
                        Task {
                            if await model.save() { dismiss() }
                        }
                    }
                    .disabled(model.isSaving)
                }
            }
            .sheet(isPresented: $isAddingActivity) {
                ActivityEditorSheet { activity in
                    model.activities.append(activity)
                }
            }
            .alert("无法保存计划", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "请稍后重试。")
            }
        }
    }
}

private enum ActivityKind: String, CaseIterable, Identifiable {
    case strength
    case cardio

    var id: String { rawValue }
    var title: String { self == .strength ? "力量" : "有氧" }
    var symbolName: String { self == .strength ? "dumbbell.fill" : "figure.run" }
}

fileprivate struct ActivityDraft: Identifiable {
    let id: UUID
    var name: String
    var kind: ActivityKind
    var setCount: String
    var repetitions: String
    var load: String
    var durationMinutes: String

    init(
        id: UUID = UUID(), name: String, kind: ActivityKind,
        setCount: String = "3", repetitions: String = "8", load: String = "",
        durationMinutes: String = "20"
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.setCount = setCount
        self.repetitions = repetitions
        self.load = load
        self.durationMinutes = durationMinutes
    }

    init(_ activity: PlannedActivity) {
        id = activity.id
        name = activity.name
        switch activity.details {
        case let .strength(plan):
            kind = .strength
            setCount = String(plan.sets.count)
            repetitions = plan.sets.first?.repetitions.map(String.init) ?? ""
            load = plan.sets.first?.load.map { DecimalDisplay.string($0.value) } ?? ""
            durationMinutes = ""
        case let .cardio(plan):
            kind = .cardio
            setCount = ""
            repetitions = ""
            load = ""
            durationMinutes = plan.segments.first?.durationSeconds.map { String($0 / 60) } ?? ""
        }
    }

    var summary: String {
        switch kind {
        case .strength:
            let count = setCount.isEmpty ? "若干" : setCount
            let reps = repetitions.isEmpty ? "自由次数" : "\(repetitions) 次"
            let weight = load.isEmpty ? "" : " · \(load) kg"
            return "\(count) 组 · \(reps)\(weight)"
        case .cardio:
            return durationMinutes.isEmpty ? "时长待定" : "\(durationMinutes) 分钟"
        }
    }

    var commandInput: PlannedActivityInput {
        switch kind {
        case .strength:
            return PlannedActivityInput(
                id: nil, name: name, notes: nil,
                details: .strength(.uniform(
                    setCount: Int(setCount) ?? 0,
                    target: StrengthSetTargetInput(
                        repetitions: Int(repetitions),
                        load: DecimalDisplay.load(from: load), rpe: nil, note: nil
                    )
                ))
            )
        case .cardio:
            return PlannedActivityInput(
                id: nil, name: name, notes: nil,
                details: .cardio(CardioPlanInput(segments: [CardioSegmentTargetInput(
                    durationSeconds: Int(durationMinutes).map { $0 * 60 },
                    distance: nil, targetHeartRate: nil, note: nil
                )]))
            )
        }
    }
}

private struct ActivityEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ActivityKind = .strength
    @State private var name = ""
    @State private var setCount = "3"
    @State private var repetitions = "8"
    @State private var load = ""
    @State private var durationMinutes = "20"
    let onSave: (ActivityDraft) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Picker("类型", selection: $kind) {
                    ForEach(ActivityKind.allCases) { kind in Text(kind.title).tag(kind) }
                }
                TextField(kind == .strength ? "项目名称，例如：深蹲" : "项目名称，例如：跑步机", text: $name)

                if kind == .strength {
                    TextField("组数", text: $setCount).keyboardType(.numberPad)
                    TextField("每组次数（可选）", text: $repetitions).keyboardType(.numberPad)
                    TextField("重量 kg（可选）", text: $load).keyboardType(.decimalPad)
                } else {
                    TextField("时长（分钟）", text: $durationMinutes).keyboardType(.numberPad)
                }
            }
            .navigationTitle("添加项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        onSave(ActivityDraft(
                            name: name, kind: kind, setCount: setCount,
                            repetitions: repetitions, load: load, durationMinutes: durationMinutes
                        ))
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Workout Feature

@MainActor
@Observable
final class WorkoutFeatureModel {
    private let application: any TrainingApplication
    var snapshot: WorkoutSnapshot
    var errorMessage: String?
    var isFinishing = false

    init(application: any TrainingApplication, snapshot: WorkoutSnapshot) {
        self.application = application
        self.snapshot = snapshot
    }

    func completeStrengthSet(_ set: StrengthSetResult, repetitions: Int? = nil, load: Load? = nil) async {
        await execute {
            .recordStrengthSet(RecordStrengthSetCommand(
                idempotencyKey: UUID(), source: .manual, sessionID: self.snapshot.id,
                expectedRevision: self.snapshot.revision, performedSetID: set.id,
                actualRepetitions: repetitions, actualLoad: load, actualRPE: nil, note: nil
            ))
        }
    }

    func completeCardioSegment(_ segment: CardioSegmentResult, duration: Int? = nil) async {
        await execute {
            .recordCardioSegment(RecordCardioSegmentCommand(
                idempotencyKey: UUID(), source: .manual, sessionID: self.snapshot.id,
                expectedRevision: self.snapshot.revision, performedSegmentID: segment.id,
                actualDurationSeconds: duration, actualDistance: nil, note: nil
            ))
        }
    }

    func finish(feedback: SubjectiveFeedback?) async -> Bool {
        isFinishing = true
        defer { isFinishing = false }
        do {
            _ = try await application.execute(.completeWorkout(CompleteWorkoutCommand(
                idempotencyKey: UUID(), source: .manual, sessionID: snapshot.id,
                expectedRevision: snapshot.revision, feedback: feedback
            )))
            return true
        } catch {
            errorMessage = UserFacingError.message(for: error)
            return false
        }
    }

    private func execute(_ makeCommand: () -> TrainingCommand) async {
        do {
            let mutation = try await application.execute(makeCommand())
            if case let .workoutUpdated(updated) = mutation { snapshot = updated }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}

private struct WorkoutFeatureView: View {
    @State private var model: WorkoutFeatureModel
    @State private var showingFinish = false
    @State private var editingStrengthSet: StrengthSetResult?
    @State private var editingCardioSegment: CardioSegmentResult?
    let onWorkoutFinished: () async -> Void

    init(
        application: any TrainingApplication,
        initialSnapshot: WorkoutSnapshot,
        onWorkoutFinished: @escaping () async -> Void
    ) {
        _model = State(initialValue: WorkoutFeatureModel(application: application, snapshot: initialSnapshot))
        self.onWorkoutFinished = onWorkoutFinished
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.snapshot.planSnapshot.title)
                            .font(.title3.bold())
                        Text("已开始 \(model.snapshot.startedAt.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                ForEach(model.snapshot.activities) { activity in
                    Section(activity.name) {
                        activityRows(activity)
                    }
                }

                Section {
                    Button("结束训练") { showingFinish = true }
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("训练中")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingStrengthSet) { set in
                StrengthResultEditor(set: set) { reps, load in
                    Task { await model.completeStrengthSet(set, repetitions: reps, load: load) }
                }
            }
            .sheet(item: $editingCardioSegment) { segment in
                CardioResultEditor(segment: segment) { seconds in
                    Task { await model.completeCardioSegment(segment, duration: seconds) }
                }
            }
            .sheet(isPresented: $showingFinish) {
                FinishWorkoutSheet(isFinishing: model.isFinishing) { feedback in
                    if await model.finish(feedback: feedback) {
                        await onWorkoutFinished()
                        return true
                    }
                    return false
                }
                .presentationDetents([.height(390)])
            }
            .alert("暂时无法保存", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "请稍后重试。")
            }
        }
    }

    @ViewBuilder
    private func activityRows(_ activity: PerformedActivity) -> some View {
        switch activity.details {
        case let .strength(sets):
            ForEach(sets) { set in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("第 \(sets.firstIndex(where: { $0.id == set.id }).map { $0 + 1 } ?? 1) 组")
                        Text(strengthDescription(set))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if set.status == .completed {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Menu {
                            Button("按计划完成") { Task { await model.completeStrengthSet(set) } }
                            Button("填写实际结果") { editingStrengthSet = set }
                        } label: {
                            Text("记录")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        case let .cardio(segments):
            ForEach(segments) { segment in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("第 \(segments.firstIndex(where: { $0.id == segment.id }).map { $0 + 1 } ?? 1) 段")
                        Text(cardioDescription(segment))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if segment.status == .completed {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Menu {
                            Button("按计划完成") { Task { await model.completeCardioSegment(segment) } }
                            Button("填写实际时长") { editingCardioSegment = segment }
                        } label: {
                            Text("记录")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func strengthDescription(_ set: StrengthSetResult) -> String {
        let planned = plannedStrengthTarget(for: set.plannedSetID)
        let reps = set.actualRepetitions ?? planned?.repetitions
        let load = set.actualLoad ?? planned?.load
        return "\(reps.map { "\($0) 次" } ?? "次数待定")\(load.map { " · \(DecimalDisplay.string($0.value)) \($0.unit.displayName)" } ?? "")"
    }

    private func cardioDescription(_ segment: CardioSegmentResult) -> String {
        let planned = plannedCardioTarget(for: segment.plannedSegmentID)
        let seconds = segment.actualDurationSeconds ?? planned?.durationSeconds
        return seconds.map { "\($0 / 60) 分钟" } ?? "时长待定"
    }

    private func plannedStrengthTarget(for id: UUID?) -> StrengthSetTarget? {
        for activity in model.snapshot.planSnapshot.projection.activities {
            if case let .strength(plan) = activity.details,
               let target = plan.sets.first(where: { $0.id == id }) { return target }
        }
        return nil
    }

    private func plannedCardioTarget(for id: UUID?) -> CardioSegmentTarget? {
        for activity in model.snapshot.planSnapshot.projection.activities {
            if case let .cardio(plan) = activity.details,
               let target = plan.segments.first(where: { $0.id == id }) { return target }
        }
        return nil
    }
}

private struct StrengthResultEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var repetitions: String
    @State private var load: String
    let onSave: (Int?, Load?) -> Void

    init(set: StrengthSetResult, onSave: @escaping (Int?, Load?) -> Void) {
        _repetitions = State(initialValue: set.actualRepetitions.map(String.init) ?? "")
        _load = State(initialValue: set.actualLoad.map { DecimalDisplay.string($0.value) } ?? "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("实际次数（留空则沿用计划）", text: $repetitions).keyboardType(.numberPad)
                TextField("实际重量 kg（留空则沿用计划）", text: $load).keyboardType(.decimalPad)
            }
            .navigationTitle("记录本组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(Int(repetitions), DecimalDisplay.load(from: load))
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct CardioResultEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: String
    let onSave: (Int?) -> Void

    init(segment: CardioSegmentResult, onSave: @escaping (Int?) -> Void) {
        _minutes = State(initialValue: segment.actualDurationSeconds.map { String($0 / 60) } ?? "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("实际时长（分钟，留空则沿用计划）", text: $minutes).keyboardType(.numberPad)
            }
            .navigationTitle("记录有氧")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(Int(minutes).map { $0 * 60 })
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct FinishWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var effort: PerceivedEffort?
    @State private var notes = ""
    let isFinishing: Bool
    let onConfirm: (SubjectiveFeedback?) async -> Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Text("完成这次训练？")
                    .font(.title2.bold())
                Text("尚未记录的训练段会标记为跳过，计划值始终保留不变。")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Text("主观感受（可选）")
                        .font(.subheadline.weight(.semibold))
                    Picker("主观感受", selection: $effort) {
                        Text("未选择").tag(PerceivedEffort?.none)
                        Text("轻松").tag(PerceivedEffort?.some(.easy))
                        Text("适中").tag(PerceivedEffort?.some(.moderate))
                        Text("吃力").tag(PerceivedEffort?.some(.hard))
                    }
                    .pickerStyle(.segmented)
                }

                TextField("训练备注（可选）", text: $notes, axis: .vertical)
                    .lineLimit(2...3)
                    .textFieldStyle(.roundedBorder)

                Button(isFinishing ? "保存中" : "确认完成") {
                    Task {
                        let feedback = effort == nil && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? nil
                            : SubjectiveFeedback(perceivedEffort: effort, notes: notes.isEmpty ? nil : notes)
                        if await onConfirm(feedback) { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(TrainingAppearance.action)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(isFinishing)
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("继续训练") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Training Record Feature

private struct TrainingRecordFeatureView: View {
    let record: TrainingRecord
    let onRefresh: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(record.status.displayName, systemImage: "checkmark.seal.fill")
                            .foregroundStyle(record.status == .completed ? .green : .orange)
                        Text(record.title).font(.title2.bold())
                        Text("训练时长 \(record.durationSeconds / 60) 分钟")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                ForEach(record.activities) { activity in
                    Section(activity.name) { recordRows(activity) }
                }
            }
            .navigationTitle("今日训练记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("刷新", action: onRefresh) } }
        }
    }

    @ViewBuilder
    private func recordRows(_ activity: TrainingRecordActivity) -> some View {
        switch activity.details {
        case let .strength(sets):
            ForEach(sets) { set in
                VStack(alignment: .leading, spacing: 4) {
                    Text("第 \(sets.firstIndex(where: { $0.id == set.id }).map { $0 + 1 } ?? 1) 组")
                    Text("实际：\(set.actualRepetitions.map { "\($0) 次" } ?? "未完成")\(set.actualLoad.map { " · \(DecimalDisplay.string($0.value)) \($0.unit.displayName)" } ?? "")")
                        .foregroundStyle(.secondary)
                    if set.hasDeviation { Text("与计划不同").font(.footnote).foregroundStyle(.orange) }
                }
            }
        case let .cardio(segments):
            ForEach(segments) { segment in
                VStack(alignment: .leading, spacing: 4) {
                    Text("第 \(segments.firstIndex(where: { $0.id == segment.id }).map { $0 + 1 } ?? 1) 段")
                    Text("实际：\(segment.actualDurationSeconds.map { "\($0 / 60) 分钟" } ?? "未完成")")
                        .foregroundStyle(.secondary)
                    if segment.hasDeviation { Text("与计划不同").font(.footnote).foregroundStyle(.orange) }
                }
            }
        }
    }
}

// MARK: - Presentation helpers

private enum DecimalDisplay {
    static func string(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    static func load(from text: String) -> Load? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Decimal(string: trimmed) else { return nil }
        return Load(value: value, unit: .kilogram)
    }
}

private enum TrainingAppearance {
    static let card = Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
    static let action = Color(red: 48 / 255, green: 48 / 255, blue: 48 / 255)
}

private enum UserFacingError {
    static func message(for error: Error) -> String {
        guard let applicationError = error as? TrainingApplicationError else {
            return "本地数据暂时不可用，请稍后再试。"
        }
        switch applicationError {
        case .invalidPlan:
            return "请填写计划名称，并为每个项目提供有效的训练目标。"
        case .invalidWorkout:
            return "训练数据不完整，请检查输入后重试。"
        case .activePlanAlreadyExists:
            return "今天已经有一个未完成计划，请先编辑它。"
        case .planNotFound, .workoutNotFound:
            return "没有找到这条训练数据，请刷新页面。"
        case .planNotConfirmed:
            return "请先保存并确认计划。"
        case .activeWorkoutAlreadyExists:
            return "已有一场训练正在进行中。"
        case .workoutAlreadyFinished:
            return "这场训练已经结束。"
        case .workoutNotFinished:
            return "训练尚未结束。"
        case .segmentNotFound:
            return "没有找到要记录的训练段，请刷新页面。"
        case .staleRevision:
            return "数据已经更新，请刷新后再试。"
        case .idempotencyKeyConflict:
            return "这次操作与先前请求冲突，请重新操作。"
        case .persistenceFailure:
            return "本地保存失败，请稍后重试。"
        }
    }
}

private extension WorkoutStatus {
    var displayName: String {
        switch self {
        case .inProgress: "进行中"
        case .completed: "已完成"
        case .partiallyCompleted: "部分完成"
        case .interrupted: "已中断"
        }
    }
}

private extension LoadUnit {
    var displayName: String { self == .kilogram ? "kg" : "lb" }
}
