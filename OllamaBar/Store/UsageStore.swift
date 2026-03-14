import Foundation
import Observation
@Observable
@MainActor
final class UsageStore {
    private(set) var records: [UsageRecord] = []
    init(records: [UsageRecord] = [], persistence: PersistenceManager = PersistenceManager()) {}
}
