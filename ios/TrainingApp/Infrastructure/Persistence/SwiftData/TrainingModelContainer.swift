import SwiftData

/// Schema V1 的唯一入口。测试可请求内存容器，正式 App 则使用系统管理的本地持久化位置。
enum TrainingModelContainer {
    static func make(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            DailyPlanEntity.self, PlannedActivityEntity.self, PlannedSegmentEntity.self,
            PlanRevisionEntity.self, WorkoutSessionEntity.self, PerformedActivityEntity.self,
            PerformedSegmentEntity.self, IdempotencyRecordEntity.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isStoredInMemoryOnly)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
