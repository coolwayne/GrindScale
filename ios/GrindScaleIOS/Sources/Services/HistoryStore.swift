import Foundation

final class HistoryStore {
    private let defaults = UserDefaults.standard
    private let key = "grindscale.analysis.history"
    private let maxRecords = 30

    func load() -> [AnalysisHistoryRecord] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([AnalysisHistoryRecord].self, from: data) else {
            return []
        }
        return records.sorted { $0.timestamp > $1.timestamp }
    }

    func save(record: AnalysisHistoryRecord) {
        var records = load()
        records.insert(record, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: key)
        }
    }
}
