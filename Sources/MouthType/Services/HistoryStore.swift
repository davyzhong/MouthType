import Foundation
import os
#if canImport(SQLite)
import SQLite
#endif

private let historyLog = RedactedLogger(subsystem: "com.mouthtype", category: "HistoryStore")

final class HistoryStore {
    static let shared = HistoryStore()

#if canImport(SQLite)
    private var db: Connection?
    private let table = Table("transcriptions")
    private let id = Expression<Int64>("id")
    private let text = Expression<String>("text")
    private let timestamp = Expression<Date>("timestamp")
    private let processedText = Expression<String?>("processed_text")
#endif

    private init() {
#if canImport(SQLite)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MouthType", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("Database.sqlite")

        do {
            db = try Connection(dbURL.path)
            try db?.run(table.create(ifNotExists: true) { t in
                t.column(id, primaryKey: .autoincrement)
                t.column(text)
                t.column(timestamp)
                t.column(processedText)
            })
        } catch {
            historyLog.error("Failed to open database: \(error)")
            db = nil
        }
#endif
    }

    func insert(raw: String, processed: String? = nil) {
        guard !UITestConfiguration.current.isEnabled else { return }
#if canImport(SQLite)
        guard let db else { return }
        do {
            try db.run(table.insert(
                text <- raw,
                timestamp <- Date(),
                processedText <- processed
            ))
        } catch {
            historyLog.error("Insert failed: \(error)")
        }
#endif
    }

    func recent(limit: Int = 50) -> [HistoryEntry] {
        if UITestConfiguration.current.isEnabled {
            return Array(UITestConfiguration.current.historyEntries.prefix(limit))
        }
#if canImport(SQLite)
        guard let db else { return [] }
        do {
            let query = table.order(timestamp.desc).limit(limit)
            return try db.prepare(query).map { row in
                HistoryEntry(
                    id: row[id],
                    text: row[text],
                    timestamp: row[timestamp],
                    processedText: row[processedText]
                )
            }
        } catch {
            historyLog.error("Query failed: \(error)")
        }
#endif
        return []
    }

    func search(keyword: String, limit: Int = 50) -> [HistoryEntry] {
        if UITestConfiguration.current.isEnabled {
            let entries = UITestConfiguration.current.historyEntries
            guard !keyword.isEmpty else {
                return Array(entries.prefix(limit))
            }
            let filtered = entries.filter {
                $0.text.localizedCaseInsensitiveContains(keyword) ||
                ($0.processedText?.localizedCaseInsensitiveContains(keyword) ?? false)
            }
            return Array(filtered.prefix(limit))
        }
#if canImport(SQLite)
        guard let db, !keyword.isEmpty else { return recent(limit: limit) }
        do {
            let query = table.filter(text.like("%\(keyword)%")).order(timestamp.desc).limit(limit)
            return try db.prepare(query).map { row in
                HistoryEntry(
                    id: row[id],
                    text: row[text],
                    timestamp: row[timestamp],
                    processedText: row[processedText]
                )
            }
        } catch {
            historyLog.error("Search failed: \(error)")
        }
#endif
        return []
    }

    func delete(entryId: Int64) {
        guard !UITestConfiguration.current.isEnabled else { return }
#if canImport(SQLite)
        guard let db else { return }
        let target = table.filter(id == entryId)
        _ = try? db.run(target.delete())
#endif
    }

    func deleteAll() {
        guard !UITestConfiguration.current.isEnabled else { return }
#if canImport(SQLite)
        guard let db else { return }
        _ = try? db.run(table.delete())
#endif
    }

    func exportAll() -> String {
        if UITestConfiguration.current.isEnabled {
            return UITestConfiguration.current.historyEntries.map { entry in
                let raw = entry.text
                let processed = entry.processedText ?? ""
                let ts = entry.timestamp.formatted()
                return "[\(ts)]\n原文：\(raw)\(processed.isEmpty ? "" : "\n整理：\(processed)")\n"
            }.joined(separator: "\n---\n\n")
        }
#if canImport(SQLite)
        guard let db else { return "" }
        do {
            let query = table.order(timestamp.desc)
            let entries = try db.prepare(query).map { row in
                let raw = row[text]
                let processed = row[processedText] ?? ""
                let ts = row[timestamp].formatted()
                return "[\(ts)]\n原文：\(raw)\(processed.isEmpty ? "" : "\n整理：\(processed)")\n"
            }
            return entries.joined(separator: "\n---\n\n")
        } catch {
            historyLog.error("Export failed: \(error)")
        }
#endif
        return ""
    }

    func deleteOlderThan(days: Int) {
        guard !UITestConfiguration.current.isEnabled else { return }
#if canImport(SQLite)
        guard let db else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let target = table.filter(timestamp < cutoff)
        _ = try? db.run(target.delete())
#endif
    }

    func count() -> Int {
        if UITestConfiguration.current.isEnabled {
            return UITestConfiguration.current.historyEntries.count
        }
#if canImport(SQLite)
        guard let db else { return 0 }
        do {
            return try db.scalar(table.select(id).count)
        } catch {
            return 0
        }
#else
        return 0
#endif
    }
}

struct HistoryEntry: Identifiable {
    let id: Int64
    let text: String
    let timestamp: Date
    let processedText: String?
}

// MARK: - UITestConfiguration Extension

extension UITestConfiguration {
    var historyEntries: [HistoryEntry] {
        get { [] }
        set { }
    }

    var historySearchKeyword: String {
        get { "" }
        set { }
    }
}
