import Foundation

struct VaultTask: Codable {
    let path: String
    let line: Int
    let rawLine: String
    let text: String
    let checked: Bool
    let heading: String
}

final class TaskStore {
    private let root: URL
    private let lock = NSLock()
    init(root: URL) { self.root = root.standardizedFileURL }

    func list() throws -> [VaultTask] {
        lock.lock()
        defer { lock.unlock() }
        return try listUnlocked()
    }

    /// Changes only the ASCII checkbox marker; expectedLine is the exact rawLine from list().
    /// The lock serializes this instance; coordination also cooperates with macOS document writers.
    func toggle(path: String, line: Int, expectedLine: String, checked: Bool) throws -> [VaultTask] {
        lock.lock()
        defer { lock.unlock() }
        let url = try scopedURL(path)
        var coordinationError: NSError?
        var operationError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                let validated = try scopedURL(path)
                guard validated.standardizedFileURL == coordinatedURL.standardizedFileURL else { throw StoreError.concurrentChange }
                let original = try Data(contentsOf: validated)
                guard let parsed = try parse(original, path: path).first(where: { $0.task.line == line }),
                      parsed.task.rawLine.utf8.elementsEqual(expectedLine.utf8) else { throw StoreError.staleTask }
                // Preserve uppercase X when the requested state is already checked.
                guard parsed.task.checked != checked else { return }
                var changed = original
                changed[parsed.markerOffset] = checked ? 120 : 32
                // Reject any intervening edit, even if it affected a different line.
                _ = try scopedURL(path)
                guard try Data(contentsOf: validated) == original else { throw StoreError.concurrentChange }
                try changed.write(to: validated, options: .atomic)
            } catch { operationError = error }
        }
        if let error = operationError { throw error }
        if let error = coordinationError { throw error }
        return try listUnlocked()
    }

    private struct ParsedTask {
        let task: VaultTask
        let markerOffset: Int
    }
    private static let checkbox = try! NSRegularExpression(pattern: "^[ \\t]*(?:[-*+]|[0-9]+[.)])[ \\t]+\\[([ xX])\\](?:[ \\t]+(.*))?$")
    private static let headingPattern = try! NSRegularExpression(pattern: "^ {0,3}(#{1,6})(?:[ \\t]+(.*)|[ \\t]*)$")
    private static let fencePattern = try! NSRegularExpression(pattern: "^[ \\t]*(`{3,}|~{3,})(.*)$")

    private func parse(_ data: Data, path: String) throws -> [ParsedTask] {
        guard String(data: data, encoding: .utf8) != nil else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let bytes = Array(data)
        var result: [ParsedTask] = []
        var headings: [(Int, String)] = []
        var frontmatter = false
        var fence: (Character, Int)?
        var start = 0
        var lineNumber = 0
        while start < bytes.count {
            let end = bytes[start...].firstIndex(of: 10) ?? bytes.count
            var contentEnd = end
            if contentEnd > start && bytes[contentEnd - 1] == 13 { contentEnd -= 1 }
            var contentStart = start
            if start == 0 && bytes.starts(with: [239, 187, 191]) { contentStart += 3 }
            let raw = String(decoding: bytes[contentStart..<contentEnd], as: UTF8.self)
            let ns = raw as NSString
            let range = NSRange(location: 0, length: ns.length)
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if lineNumber == 0 && trimmed == "---" {
                frontmatter = true
            } else if frontmatter {
                if trimmed == "---" || trimmed == "..." { frontmatter = false }
            } else if let match = Self.fencePattern.firstMatch(in: raw, range: range) {
                let run = ns.substring(with: match.range(at: 1))
                let suffix = ns.substring(with: match.range(at: 2))
                if let open = fence {
                    if run.first == open.0 && run.count >= open.1 && suffix.trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                } else if run.first != "`" || !suffix.contains("`") {
                    fence = (run.first!, run.count)
                }
            } else if fence == nil {
                if let match = Self.headingPattern.firstMatch(in: raw, range: range) {
                    let level = match.range(at: 1).length
                    var title = match.range(at: 2).location == NSNotFound ? "" : ns.substring(with: match.range(at: 2))
                    title = title.replacingOccurrences(of: "[ \\t]+#+[ \\t]*$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                    headings.removeAll { $0.0 >= level }
                    if !title.isEmpty { headings.append((level, title)) }
                } else if let match = Self.checkbox.firstMatch(in: raw, range: range), match.range(at: 2).location != NSNotFound {
                    let text = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        let prefix = ns.substring(to: match.range(at: 1).location)
                        let marker = ns.substring(with: match.range(at: 1))
                        result.append(ParsedTask(task: VaultTask(path: path, line: lineNumber, rawLine: raw, text: text, checked: marker != " ", heading: headings.map { $0.1 }.joined(separator: " / ")), markerOffset: contentStart + prefix.utf8.count))
                    }
                }
            }
            start = end + 1
            lineNumber += 1
        }
        return result
    }

    private func excluded(_ component: String) -> Bool {
        component.hasPrefix(".") || ["_templates", "templates", "pomodoro"].contains(component.lowercased())
    }

    enum StoreError: LocalizedError {
        case invalidPath
        case staleTask
        case concurrentChange
        var errorDescription: String? {
            switch self {
            case .invalidPath: return "This task is outside the allowed Markdown vault."
            case .staleTask: return "Task changed in Obsidian. Refresh and try again."
            case .concurrentChange: return "The note changed while saving. Refresh and try again."
            }
        }
    }

    private func scopedURL(_ path: String) throws -> URL {
        let components = path.components(separatedBy: "/")
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\u{0}"),
              components.allSatisfy({ !$0.isEmpty && $0 != ".." && $0 != "." && !excluded($0) }),
              (path as NSString).pathExtension.lowercased() == "md" else { throw StoreError.invalidPath }
        var url = root
        for component in components {
            url.appendPathComponent(component)
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw StoreError.invalidPath }
        }
        guard url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/"),
              try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw StoreError.invalidPath }
        return url
    }

    private func listUnlocked() throws -> [VaultTask] {
        var tasks: [VaultTask] = []
        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey])
        guard rootValues.isDirectory == true, FileManager.default.isReadableFile(atPath: root.path) else {
            throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: root.path])
        }
        var traversalError: Error?
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles], errorHandler: { _, error in traversalError = error; return false }) else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: root.path])
        }
        for case let url as URL in files {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
            if values.isSymbolicLink == true || excluded(url.lastPathComponent) {
                files.skipDescendants()
                continue
            }
            guard values.isRegularFile == true, url.pathExtension.lowercased() == "md" else { continue }
            let path = String(url.path.dropFirst(root.path.count + 1))
            _ = try scopedURL(path)
            tasks += try parse(Data(contentsOf: url), path: path).map(\.task)
        }
        if let error = traversalError { throw error }
        return tasks.sorted { ($0.path, $0.line) < ($1.path, $1.line) }
    }
}
