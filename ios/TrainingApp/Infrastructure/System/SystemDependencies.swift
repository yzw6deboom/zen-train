import Foundation

struct SystemTrainingClock: TrainingClock {
    func now() async -> Date {
        Date()
    }
}

struct UUIDGenerator: IDGenerator {
    func next() async -> UUID {
        UUID()
    }
}
