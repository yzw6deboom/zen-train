import Observation
import SwiftUI

/// 组合根只负责注入依赖；一级导航、跨 Feature 路由和启动恢复收敛在 App Shell。
struct AppRootView: View {
    @State private var shell: AppShellFeatureModel

    init(environment: AppEnvironment, trainingApplication: any TrainingApplication) {
        _shell = State(initialValue: AppShellFeatureModel(
            environment: environment,
            application: trainingApplication
        ))
    }

    var body: some View {
        AppShellView(model: shell)
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

fileprivate struct PlanEditorFeatureView: View {
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
            ScrollView {
                VStack(alignment: .leading, spacing: ZenSpace.s24) {
                    ZenPageHeader(eyebrow: "建立今日训练", title: "计划编辑")
                    SurfaceCard {
                        Text("计划名称").font(.subheadline.weight(.semibold))
                        TextField("例如：下肢力量", text: $model.title)
                            .textFieldStyle(.plain)
                            .padding(ZenSpace.s12)
                            .background(ZenColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10))
                        Text("备注（可选）").font(.subheadline.weight(.semibold)).padding(.top, ZenSpace.s8)
                        TextField("写下今天的训练重点", text: $model.notes, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.plain)
                            .padding(ZenSpace.s12)
                            .background(ZenColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10))
                    }
                    VStack(alignment: .leading, spacing: ZenSpace.s12) {
                        Text("训练项目").font(.headline)
                        ForEach(model.activities) { activity in
                            SurfaceCard {
                                HStack(spacing: ZenSpace.s12) {
                                    Image(systemName: activity.kind.symbolName)
                                        .foregroundStyle(ZenColor.actionPrimary).frame(width: 24)
                                    VStack(alignment: .leading, spacing: ZenSpace.s4) {
                                        Text(activity.name).font(.body.weight(.semibold))
                                        Text(activity.summary).font(.caption).foregroundStyle(ZenColor.textSecondary)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        model.activities.removeAll { $0.id == activity.id }
                                    } label: { Image(systemName: "trash") }
                                    .accessibilityLabel("删除 \(activity.name)")
                                }
                            }
                        }
                        SecondaryActionButton("添加训练项目") { isAddingActivity = true }
                        Text("力量项目会按每一组保存目标；有氧项目目前记录时长。")
                            .font(.caption).foregroundStyle(ZenColor.textSecondary)
                    }
                }
                .padding(.horizontal, ZenSpace.s16)
                .padding(.vertical, ZenSpace.s24)
            }
            .background(ZenColor.backgroundPrimary)
            .navigationTitle("创建今日计划")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(model.isSaving ? "保存中" : "保存计划") {
                    Task { if await model.save() { dismiss() } }
                }
                .disabled(model.isSaving)
                .padding(.horizontal, ZenSpace.s16)
                .padding(.vertical, ZenSpace.s8)
                .background(ZenColor.backgroundPrimary)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
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
            ScrollView {
                VStack(alignment: .leading, spacing: ZenSpace.s24) {
                    ZenPageHeader(eyebrow: "补充今天的训练", title: "添加项目")
                    SurfaceCard {
                        Picker("类型", selection: $kind) {
                            ForEach(ActivityKind.allCases) { kind in Text(kind.title).tag(kind) }
                        }
                        .pickerStyle(.segmented)
                        EditorField(title: "项目名称", placeholder: kind == .strength ? "例如：深蹲" : "例如：跑步机", text: $name)
                    }
                    SurfaceCard {
                        if kind == .strength {
                            EditorField(title: "组数", placeholder: "3", text: $setCount, keyboard: .numberPad)
                            EditorField(title: "每组次数（可选）", placeholder: "8", text: $repetitions, keyboard: .numberPad)
                            EditorField(title: "重量 kg（可选）", placeholder: "例如：40", text: $load, keyboard: .decimalPad)
                        } else {
                            EditorField(title: "时长（分钟）", placeholder: "20", text: $durationMinutes, keyboard: .numberPad)
                        }
                    }
                }
                .padding(.horizontal, ZenSpace.s16)
                .padding(.vertical, ZenSpace.s24)
            }
            .background(ZenColor.backgroundPrimary)
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

fileprivate struct WorkoutFeatureView: View {
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
            ScrollView {
                VStack(alignment: .leading, spacing: ZenSpace.s16) {
                    ZenPageHeader(eyebrow: "已开始 \(model.snapshot.startedAt.formatted(date: .omitted, time: .shortened))", title: model.snapshot.planSnapshot.title)
                    SurfaceCard {
                        Text("训练进度").font(.caption.weight(.semibold)).foregroundStyle(ZenColor.textSecondary)
                        ProgressView(value: completedSegmentCount, total: totalSegmentCount).tint(ZenColor.statusSuccess)
                        Text("已记录 \(Int(completedSegmentCount)) / \(Int(totalSegmentCount)) 组或训练段")
                            .font(.subheadline).foregroundStyle(ZenColor.textSecondary)
                    }
                    ForEach(model.snapshot.activities) { activity in
                        SurfaceCard {
                            Text(activity.name).font(.headline)
                            activityRows(activity)
                        }
                    }
                }
                .padding(.horizontal, ZenSpace.s16)
                .padding(.vertical, ZenSpace.s24)
            }
            .background(ZenColor.backgroundPrimary)
            .navigationTitle("训练中")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                SecondaryActionButton("结束训练") { showingFinish = true }
                    .foregroundStyle(.red)
                    .padding(.horizontal, ZenSpace.s16)
                    .padding(.vertical, ZenSpace.s8)
                    .background(ZenColor.backgroundPrimary)
            }
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

    private var totalSegmentCount: Double {
        Double(model.snapshot.activities.reduce(0) { partial, activity in
            switch activity.details {
            case let .strength(sets): partial + sets.count
            case let .cardio(segments): partial + segments.count
            }
        })
    }

    private var completedSegmentCount: Double {
        Double(model.snapshot.activities.reduce(0) { partial, activity in
            switch activity.details {
            case let .strength(sets): partial + sets.filter { $0.status == .completed }.count
            case let .cardio(segments): partial + segments.filter { $0.status == .completed }.count
            }
        })
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
            VStack(alignment: .leading, spacing: ZenSpace.s24) {
                ZenPageHeader(eyebrow: "可随时修正", title: "记录本组")
                SurfaceCard {
                    EditorField(title: "实际次数", placeholder: "留空则沿用计划", text: $repetitions, keyboard: .numberPad)
                    EditorField(title: "实际重量 kg", placeholder: "留空则沿用计划", text: $load, keyboard: .decimalPad)
                }
                Spacer()
                PrimaryActionButton("保存本组结果") {
                    onSave(Int(repetitions), DecimalDisplay.load(from: load))
                    dismiss()
                }
            }
            .padding(ZenSpace.s24)
            .background(ZenColor.backgroundPrimary)
            .navigationTitle("记录本组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
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
            VStack(alignment: .leading, spacing: ZenSpace.s24) {
                ZenPageHeader(eyebrow: "可随时修正", title: "记录有氧")
                SurfaceCard {
                    EditorField(title: "实际时长（分钟）", placeholder: "留空则沿用计划", text: $minutes, keyboard: .numberPad)
                }
                Spacer()
                PrimaryActionButton("保存训练结果") {
                    onSave(Int(minutes).map { $0 * 60 })
                    dismiss()
                }
            }
            .padding(ZenSpace.s24)
            .background(ZenColor.backgroundPrimary)
            .navigationTitle("记录有氧")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
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

// MARK: - App Shell

/// App Shell 只保存展示状态：选中的一级区域、编辑入口与覆盖全 App 的训练专注流程。
/// 训练是否合法、记录是否已完成，仍由 `TrainingApplication` 和 Domain 判断。
enum AppTab: Hashable, CaseIterable {
    case today
    case records
    case plans

    var title: String {
        switch self {
        case .today: "今天"
        case .records: "记录"
        case .plans: "计划"
        }
    }

    var symbolName: String {
        switch self {
        case .today: "sun.max"
        case .records: "clock.arrow.circlepath"
        case .plans: "list.bullet.rectangle"
        }
    }
}

enum AppFullScreenRoute: Identifiable {
    case workout(WorkoutSnapshot)
    case result(TrainingRecord)

    var id: UUID {
        switch self {
        case let .workout(snapshot): snapshot.id
        case let .result(record): record.sessionID
        }
    }
}

@MainActor
@Observable
final class AppShellFeatureModel {
    let environment: AppEnvironment
    let application: any TrainingApplication

    var selectedTab: AppTab = .today
    var todaySnapshot: TodaySnapshot?
    var records: [TrainingRecordSummary] = []
    var fullScreenRoute: AppFullScreenRoute?
    var isPresentingPlanEditor = false
    var editingPlan: PlanEditorSnapshot?
    var isViewingDetail = false
    var errorMessage: String?

    init(environment: AppEnvironment, application: any TrainingApplication) {
        self.environment = environment
        self.application = application
    }

    /// 启动恢复只查询既有事实：发现进行中的 Session 才恢复专注页，绝不在这里创建训练。
    func load() async {
        do {
            todaySnapshot = try await application.today(on: Calendar.current.startOfDay(for: .now))
            records = try await application.recentRecords(limit: 30)
            if let activeWorkout = try await application.activeWorkout() {
                fullScreenRoute = .workout(activeWorkout)
            }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func presentNewPlan() {
        editingPlan = nil
        isPresentingPlanEditor = true
    }

    func presentPlanEditor(_ plan: PlanEditorSnapshot) {
        editingPlan = plan
        isPresentingPlanEditor = true
    }

    func didDismissPlanEditor() async {
        await refreshContent()
    }

    func startWorkout(plan: PlanEditorSnapshot) async {
        do {
            let mutation = try await application.execute(.startWorkout(StartWorkoutCommand(
                idempotencyKey: UUID(), source: .manual, planID: plan.id, expectedRevision: plan.revision
            )))
            if case let .workoutStarted(snapshot) = mutation {
                fullScreenRoute = .workout(snapshot)
            }
            await refreshContent()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func presentResult(for sessionID: UUID) async {
        do {
            fullScreenRoute = .result(try await application.record(sessionID: sessionID))
            await refreshContent()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func returnToToday() async {
        fullScreenRoute = nil
        selectedTab = .today
        await refreshContent()
    }

    private func refreshContent() async {
        do {
            todaySnapshot = try await application.today(on: Calendar.current.startOfDay(for: .now))
            records = try await application.recentRecords(limit: 30)
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}

private struct AppShellView: View {
    @Bindable var model: AppShellFeatureModel

    var body: some View {
        Group {
            if let snapshot = model.todaySnapshot {
                tabContent(snapshot)
            } else {
                ProgressView("正在准备今天的训练")
                    .tint(ZenColor.actionPrimary)
            }
        }
        .background(ZenColor.backgroundPrimary)
        .tint(ZenColor.actionPrimary)
        .task { await model.load() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.isViewingDetail {
                ZenTabBar(selection: $model.selectedTab)
                    .padding(.horizontal, ZenSpace.s16)
                    .padding(.top, ZenSpace.s8)
            }
        }
        .sheet(isPresented: $model.isPresentingPlanEditor, onDismiss: {
            Task { await model.didDismissPlanEditor() }
        }) {
            PlanEditorFeatureView(application: model.application, existingPlan: model.editingPlan)
        }
        .fullScreenCover(item: $model.fullScreenRoute) { route in
            switch route {
            case let .workout(snapshot):
                WorkoutFeatureView(
                    application: model.application,
                    initialSnapshot: snapshot,
                    onWorkoutFinished: { await model.presentResult(for: snapshot.id) }
                )
            case let .result(record):
                WorkoutResultView(record: record) { Task { await model.returnToToday() } }
            }
        }
        .alert("暂时无法完成操作", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "请稍后重试。")
        }
    }

    @ViewBuilder
    private func tabContent(_ snapshot: TodaySnapshot) -> some View {
        switch model.selectedTab {
        case .today:
            TodayHomeView(
                snapshot: snapshot,
                onCreatePlan: model.presentNewPlan,
                onEditPlan: model.presentPlanEditor,
                onStartWorkout: { plan in Task { await model.startWorkout(plan: plan) } },
                onShowRecord: { model.selectedTab = .records }
            )
        case .records:
            RecordsHomeView(
                application: model.application,
                records: model.records,
                onDetailVisibility: { model.isViewingDetail = $0 }
            )
        case .plans:
            PlansHomeView(
                snapshot: snapshot,
                onCreatePlan: model.presentNewPlan,
                onEditPlan: model.presentPlanEditor
            )
        }
    }
}

// MARK: - 一级页面

private struct TodayHomeView: View {
    let snapshot: TodaySnapshot
    let onCreatePlan: () -> Void
    let onEditPlan: (PlanEditorSnapshot) -> Void
    let onStartWorkout: (PlanEditorSnapshot) -> Void
    let onShowRecord: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ZenSpace.s24) {
                    ZenPageHeader(eyebrow: Date.now.formatted(.dateTime.weekday(.wide).month().day()), title: "今天")
                    stateContent
                    if !snapshot.recentRecords.isEmpty {
                        VStack(alignment: .leading, spacing: ZenSpace.s12) {
                            Text("最近训练").font(.headline)
                            ForEach(snapshot.recentRecords.prefix(3), id: \.sessionID) { record in
                                TrainingRecordRow(summary: record)
                            }
                        }
                    }
                }
                .padding(.horizontal, ZenSpace.s16)
                .padding(.vertical, ZenSpace.s24)
            }
            .background(ZenColor.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch snapshot.state {
        case .noPlan:
            EmptyStateView(
                symbol: "figure.strengthtraining.traditional",
                title: "给今天留一点训练时间",
                message: "从一个简单计划开始。完成后，实际表现会被完整保留。",
                actionTitle: "创建今日计划",
                action: onCreatePlan
            )
        case let .draft(plan):
            PlanOverviewCard(plan: plan, badge: "草稿", onEdit: { onEditPlan(plan) }, onStart: nil)
        case let .ready(plan):
            PlanOverviewCard(plan: plan, badge: "已准备", onEdit: { onEditPlan(plan) }, onStart: { onStartWorkout(plan) })
        case .workoutInProgress:
            EmptyStateView(
                symbol: "figure.strengthtraining.traditional",
                title: "训练正在进行",
                message: "已恢复到上次的训练进度。",
                actionTitle: "继续训练",
                action: {}
            )
        case let .completed(record):
            SurfaceCard {
                StatusBadge(title: "今日已完成", kind: .success)
                Text(record.title).font(.title3.weight(.bold)).padding(.top, ZenSpace.s12)
                Text("训练时长 \(record.durationSeconds / 60) 分钟 · \(record.status.displayName)")
                    .font(.subheadline).foregroundStyle(ZenColor.textSecondary)
                Divider().overlay(ZenColor.divider).padding(.vertical, ZenSpace.s12)
                SecondaryActionButton("查看完整记录", action: onShowRecord)
            }
        }
    }
}

private struct PlansHomeView: View {
    let snapshot: TodaySnapshot
    let onCreatePlan: () -> Void
    let onEditPlan: (PlanEditorSnapshot) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ZenSpace.s24) {
                    ZenPageHeader(eyebrow: "今天的安排", title: "计划")
                    switch snapshot.state {
                    case let .draft(plan):
                        PlanOverviewCard(plan: plan, badge: "草稿", onEdit: { onEditPlan(plan) }, onStart: nil)
                    case let .ready(plan):
                        PlanOverviewCard(plan: plan, badge: "已准备", onEdit: { onEditPlan(plan) }, onStart: nil)
                    case let .completed(record):
                        SurfaceCard {
                            StatusBadge(title: "关联训练已完成", kind: .success)
                            Text(record.title).font(.title3.weight(.bold)).padding(.top, ZenSpace.s12)
                            Text("今天的计划已产生训练记录；编辑入口仍保留，业务规则由 Application 校验。")
                                .font(.subheadline).foregroundStyle(ZenColor.textSecondary)
                        }
                    case .noPlan, .workoutInProgress:
                        EmptyStateView(
                            symbol: "calendar.badge.plus",
                            title: "今天还没有计划",
                            message: "创建后可以在这里查看和编辑训练项目。",
                            actionTitle: "创建今日计划",
                            action: onCreatePlan
                        )
                    }
                }
                .padding(.horizontal, ZenSpace.s16)
                .padding(.vertical, ZenSpace.s24)
            }
            .background(ZenColor.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct RecordsHomeView: View {
    let application: any TrainingApplication
    let records: [TrainingRecordSummary]
    let onDetailVisibility: (Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ZenSpace.s16) {
                    ZenPageHeader(eyebrow: "已完成的训练", title: "记录")
                    if records.isEmpty {
                        EmptyStateView(
                            symbol: "clock.arrow.circlepath",
                            title: "还没有训练记录",
                            message: "完成一次训练后，它会按时间顺序出现在这里。",
                            actionTitle: nil,
                            action: {}
                        )
                    } else {
                        Text("最近 30 天").font(.headline)
                        ForEach(records, id: \.sessionID) { summary in
                            NavigationLink {
                                RecordDetailView(application: application, sessionID: summary.sessionID)
                                    .onAppear { onDetailVisibility(true) }
                                    .onDisappear { onDetailVisibility(false) }
                            } label: {
                                TrainingRecordRow(summary: summary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, ZenSpace.s16)
                .padding(.vertical, ZenSpace.s24)
            }
            .background(ZenColor.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct RecordDetailView: View {
    let application: any TrainingApplication
    let sessionID: UUID
    @State private var record: TrainingRecord?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let record {
                ScrollView {
                    VStack(alignment: .leading, spacing: ZenSpace.s16) {
                        ZenPageHeader(eyebrow: record.endedAt.formatted(date: .abbreviated, time: .shortened), title: record.title)
                        SurfaceCard {
                            StatusBadge(title: record.status.displayName, kind: record.status == .completed ? .success : .warning)
                            Text("训练时长 \(record.durationSeconds / 60) 分钟")
                                .font(.subheadline).foregroundStyle(ZenColor.textSecondary).padding(.top, ZenSpace.s12)
                        }
                        ForEach(record.activities) { activity in
                            SurfaceCard {
                                Text(activity.name).font(.headline)
                                RecordActivitySummary(activity: activity)
                            }
                        }
                        if let feedback = record.feedback, feedback.perceivedEffort != nil || feedback.notes != nil {
                            SurfaceCard {
                                Text("训练感受").font(.headline)
                                if let effort = feedback.perceivedEffort { Text(effort.displayName) }
                                if let notes = feedback.notes { Text(notes).foregroundStyle(ZenColor.textSecondary) }
                            }
                        }
                    }
                    .padding(.horizontal, ZenSpace.s16)
                    .padding(.vertical, ZenSpace.s24)
                }
            } else {
                ProgressView("正在读取训练记录")
            }
        }
        .background(ZenColor.backgroundPrimary)
        .task {
            do { record = try await application.record(sessionID: sessionID) }
            catch { errorMessage = UserFacingError.message(for: error) }
        }
        .alert("无法读取记录", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "请稍后重试。") }
    }
}

private struct WorkoutResultView: View {
    let record: TrainingRecord
    let onReturnToToday: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s24) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(ZenColor.statusSuccess, in: Circle())
            Text("本次训练完成").font(.largeTitle.weight(.bold))
            Text(record.title).font(.title3.weight(.semibold))
            Text("已保存 \(record.activities.count) 个训练项目，训练时长 \(record.durationSeconds / 60) 分钟。")
                .foregroundStyle(ZenColor.textSecondary)
            SurfaceCard {
                HStack {
                    ResultStat(value: "\(record.activities.count)", label: "训练项目")
                    Divider().frame(height: 36)
                    ResultStat(value: "\(record.durationSeconds / 60)", label: "分钟")
                    Divider().frame(height: 36)
                    ResultStat(value: record.status.displayName, label: "完成状态")
                }
            }
            Spacer()
            PrimaryActionButton("回到今天", action: onReturnToToday)
        }
        .padding(ZenSpace.s24)
        .background(ZenColor.backgroundPrimary)
    }
}

private struct RecordActivitySummary: View {
    let activity: TrainingRecordActivity

    var body: some View {
        switch activity.details {
        case let .strength(sets):
            ForEach(sets) { set in
                HStack {
                    Text("第 \(set.id == sets.first?.id ? 1 : (sets.firstIndex(where: { $0.id == set.id }) ?? 0) + 1) 组")
                    Spacer()
                    Text("\(set.actualRepetitions.map { "\($0) 次" } ?? "未完成")")
                        .foregroundStyle(ZenColor.textSecondary)
                }.font(.subheadline)
            }
        case let .cardio(segments):
            ForEach(segments) { segment in
                HStack {
                    Text("第 \(segments.firstIndex(where: { $0.id == segment.id }).map { $0 + 1 } ?? 1) 段")
                    Spacer()
                    Text(segment.actualDurationSeconds.map { "\($0 / 60) 分钟" } ?? "未完成")
                        .foregroundStyle(ZenColor.textSecondary)
                }.font(.subheadline)
            }
        }
    }
}

// MARK: - Design System

private enum ZenColor {
    static let backgroundPrimary = Color(red: 247 / 255, green: 247 / 255, blue: 244 / 255)
    static let surfacePrimary = Color.white
    static let surfaceSecondary = Color(red: 240 / 255, green: 241 / 255, blue: 237 / 255)
    static let textPrimary = Color(red: 27 / 255, green: 31 / 255, blue: 28 / 255)
    static let textSecondary = Color(red: 102 / 255, green: 112 / 255, blue: 106 / 255)
    static let actionPrimary = Color(red: 38 / 255, green: 61 / 255, blue: 50 / 255)
    static let statusSuccess = Color(red: 44 / 255, green: 122 / 255, blue: 82 / 255)
    static let statusWarning = Color(red: 166 / 255, green: 94 / 255, blue: 20 / 255)
    static let divider = Color(red: 217 / 255, green: 221 / 255, blue: 215 / 255)
}

private enum ZenSpace {
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
}

private struct ZenPageHeader: View {
    let eyebrow: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            Text(eyebrow).font(.caption.weight(.semibold)).foregroundStyle(ZenColor.textSecondary)
            Text(title).font(.system(size: 28, weight: .bold)).foregroundStyle(ZenColor.textPrimary)
        }
    }
}

private struct SurfaceCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s8) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ZenSpace.s16)
            .background(ZenColor.surfacePrimary, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(ZenColor.divider, lineWidth: 1))
    }
}

private struct PrimaryActionButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52)
        }
        .foregroundStyle(.white)
        .background(ZenColor.actionPrimary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityHint("执行主要操作")
    }
}

private struct SecondaryActionButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
        }
        .foregroundStyle(ZenColor.actionPrimary)
        .background(ZenColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 让输入控件保留系统键盘与焦点行为，同时复用页面的语义表面和间距。
private struct EditorField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s8) {
            Text(title).font(.subheadline.weight(.semibold))
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textFieldStyle(.plain)
                .padding(ZenSpace.s12)
                .background(ZenColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private enum StatusBadgeKind { case success, warning }
private struct StatusBadge: View {
    let title: String
    let kind: StatusBadgeKind
    var body: some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(kind == .success ? ZenColor.statusSuccess : ZenColor.statusWarning)
            .padding(.horizontal, ZenSpace.s8).padding(.vertical, ZenSpace.s4)
            .background((kind == .success ? ZenColor.statusSuccess : ZenColor.statusWarning).opacity(0.12), in: Capsule())
    }
}

private struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: () -> Void
    var body: some View {
        SurfaceCard {
            Image(systemName: symbol).font(.system(size: 28, weight: .medium)).foregroundStyle(ZenColor.actionPrimary)
            Text(title).font(.title3.weight(.bold)).padding(.top, ZenSpace.s8)
            Text(message).font(.subheadline).foregroundStyle(ZenColor.textSecondary)
            if let actionTitle { PrimaryActionButton(actionTitle, action: action).padding(.top, ZenSpace.s8) }
        }
    }
}

private struct PlanOverviewCard: View {
    let plan: PlanEditorSnapshot
    let badge: String
    let onEdit: () -> Void
    let onStart: (() -> Void)?
    var body: some View {
        SurfaceCard {
            StatusBadge(title: badge, kind: badge == "草稿" ? .warning : .success)
            Text(plan.title).font(.title3.weight(.bold)).padding(.top, ZenSpace.s8)
            Text("\(plan.activities.count) 个项目 · \(plan.activities.map(\.name).joined(separator: " · "))")
                .font(.subheadline).foregroundStyle(ZenColor.textSecondary).lineLimit(2)
            Divider().overlay(ZenColor.divider).padding(.vertical, ZenSpace.s8)
            if let onStart { PrimaryActionButton("开始训练", action: onStart) }
            SecondaryActionButton(badge == "草稿" ? "完善计划" : "编辑计划", action: onEdit)
        }
    }
}

private struct TrainingRecordRow: View {
    let summary: TrainingRecordSummary
    var body: some View {
        SurfaceCard {
            HStack(spacing: ZenSpace.s12) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(ZenColor.statusSuccess).font(.title3)
                VStack(alignment: .leading, spacing: ZenSpace.s4) {
                    Text(summary.title).font(.body.weight(.semibold)).foregroundStyle(ZenColor.textPrimary)
                    Text(summary.endedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(ZenColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(ZenColor.textSecondary)
            }
        }
    }
}

private struct ResultStat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            Text(value).font(.headline.monospacedDigit()).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(ZenColor.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ZenTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: ZenSpace.s4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selection = tab }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.symbolName).font(.system(size: 15, weight: .semibold))
                        Text(tab.title).font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(selection == tab ? Color.white : ZenColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(selection == tab ? ZenColor.actionPrimary : Color.clear, in: Capsule())
                }
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(ZenSpace.s8)
        .background(ZenColor.surfacePrimary, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(ZenColor.divider, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
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

private extension PerceivedEffort {
    var displayName: String {
        switch self {
        case .easy: "轻松"
        case .moderate: "适中"
        case .hard: "吃力"
        }
    }
}

private extension LoadUnit {
    var displayName: String { self == .kilogram ? "kg" : "lb" }
}
