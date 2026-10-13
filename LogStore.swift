import Foundation
import Darwin

struct LogEntry: Codable {
    let id: String
    let name: String
    let note: String
    let startedAt: Double
    let completedAt: Double
    var elapsedSeconds: Int? = nil
    var endedEarly: Bool? = nil
    var event: String? = nil
    var sessionId: String? = nil
    var plannedSeconds: Int? = nil
}

final class LogStore {
    let url: URL
    let timeZone: TimeZone
    init(url: URL, timeZone: TimeZone = .current) { self.url = url; self.timeZone = timeZone }
    private struct Pending: Codable { let id: String; let before: Data; let after: Data }
    private struct State: Codable { var ids: Set<String> = []; var pending: Pending? = nil }
    private var stateURL: URL { url.appendingPathExtension("state.json") }
    func save(_ entry: LogEntry) throws {
        let isPause = entry.event == "pause"
        let planned = entry.plannedSeconds ?? 1500
        let wallMilliseconds = entry.completedAt - entry.startedAt
        let validExplicitDuration = entry.elapsedSeconds.map { seconds in
            seconds >= 0 && Double(seconds) * 1000 <= wallMilliseconds + 1000
        } ?? (entry.endedEarly != true)
        guard (60...10800).contains(planned), planned % 60 == 0, validExplicitDuration,
              entry.endedEarly != true || (entry.elapsedSeconds ?? planned) < planned,
              isPause || entry.endedEarly == true || entry.elapsedSeconds == nil || (entry.elapsedSeconds ?? planned) >= planned,
              entry.event == nil || ["pause", "completed"].contains(entry.event!),
              !isPause || (entry.elapsedSeconds != nil && !(entry.sessionId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
              !entry.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              entry.startedAt.isFinite, entry.completedAt.isFinite,
              entry.startedAt >= 0, entry.completedAt <= 253_402_300_799_000,
              entry.completedAt >= entry.startedAt,
              (isPause || entry.endedEarly == true) ? entry.elapsedSeconds != nil : wallMilliseconds >= Double(planned) * 1000 else {
            throw NSError(domain: "AvocadoPomodoro", code: 1, userInfo: [NSLocalizedDescriptionKey: "A named, completed focus session with valid timestamps and active duration is required."])
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let stamp = formatter.string(from: Date(timeIntervalSince1970: entry.completedAt / 1000))
        // Pauses extend wall-clock time; early finishes report active rather than wall time.
        let activeSeconds = entry.elapsedSeconds ?? planned
        let elapsed = String(format: "%02d:%02d", activeSeconds / 60, activeSeconds % 60)
        let name = entry.name.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var line = "- [\(isPause ? " " : "x")] \(stamp) — \(planned / 60) min planned, \(elapsed) elapsed — \"\(name)\" — \(isPause ? "paused" : "completed")\n"
        for note in entry.note.components(separatedBy: .newlines) where !note.isEmpty { line += "  - \(note)\n" }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockFD = Darwin.open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockFD >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(lockFD) }
        guard flock(lockFD, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { flock(lockFD, LOCK_UN) }
        var state = FileManager.default.fileExists(atPath: stateURL.path) ? try JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL)) : State()
        if let pending = state.pending {
            let current = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : Data()
            if current == pending.before { try pending.after.write(to: url, options: .atomic) }
            else if current != pending.after {
                throw NSError(domain: "AvocadoPomodoro", code: 2, userInfo: [NSLocalizedDescriptionKey: "The log changed during an interrupted save. Preserve the journal and resolve the conflict before retrying."])
            }
            state.ids.insert(pending.id)
            state.pending = nil
            try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        }
        if state.ids.contains(entry.id) { return }
        let original = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : Data()
        var data = original
        if !data.isEmpty && data.last != 10 { data.append(10) }
        data.append(Data(line.utf8))
        state.pending = Pending(id: entry.id, before: original, after: data)
        try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        try data.write(to: url, options: .atomic)
        state.ids.insert(entry.id)
        state.pending = nil
        try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
    }
}
