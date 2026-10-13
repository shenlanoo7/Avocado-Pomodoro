import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(description: message) }
}
func fixture(_ body: (URL) throws -> Void) throws {
    let root = URL(fileURLWithPath: "/Users/shenlan/.hermes/cache/scratch").appendingPathComponent("task-store-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}
func put(_ root: URL, _ path: String, _ text: String) throws {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

func tryBytes(_ root: URL, _ path: String) -> Data {
    try! Data(contentsOf: root.appendingPathComponent(path))
}

func expectFailure(_ message: String, _ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw TestFailure(description: message)
}

@main struct TaskStoreTests {
    static func main() throws {
        try fixture { root in
            try put(root, "note.md", "# Work\n- [ ] Ship Unicode 中文 🚀\n")
            let tasks = try TaskStore(root: root).list()
            try expect(tasks.count == 1, "list must discover a task")
            let task = tasks[0]
            try expect(task.path == "note.md" && task.line == 1 && task.rawLine == "- [ ] Ship Unicode 中文 🚀" && task.text == "Ship Unicode 中文 🚀" && !task.checked && task.heading == "Work", "task fields")
            let encoded = try JSONEncoder().encode(task)
            let decoded = try JSONDecoder().decode(VaultTask.self, from: encoded)
            try expect(decoded.rawLine == task.rawLine, "Codable roundtrip")
        }
        print("PASS 1: discovery, task fields, Unicode, Codable")
        try fixture { root in
            let lines = ["---", "- [ ] yaml", "---", "# Parent", "## Child", "* [X] done", "  + [ ] nested", "12. [x] numbered", "2) [ ] alternate", "- [ ]   ", "```md", "- [ ] code", "```", "~~~", "+ [ ] more code", "~~~", "### Deep ###", "- [ ] deep", "# Sibling", "- [ ] sibling"]
            try put(root, "nested/note.md", "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n")
            let tasks = try TaskStore(root: root).list()
            try expect(tasks.map(\.line) == [5, 6, 7, 8, 17, 19], "frontmatter/fences/empty tasks excluded; all markers supported")
            try expect(tasks.map(\.checked) == [true, false, true, false, false, false], "case insensitive checks")
            try expect(tasks.map(\.heading) == ["Parent / Child", "Parent / Child", "Parent / Child", "Parent / Child", "Parent / Child / Deep", "Sibling"], "nested heading hierarchy")
            try expect(tasks[1].rawLine == "  + [ ] nested", "rawLine excludes CRLF but preserves indentation")
        }
        print("PASS 2: BOM/CRLF, markers, heading hierarchy, frontmatter, fences, empty tasks")
        try fixture { root in
            try put(root, "allowed/note.md", "- [ ] visible\n")
            for folder in [".hidden", ".obsidian", ".git", "_templates", "templates", "Pomodoro", "allowed/templates"] {
                try put(root, folder + "/note.md", "- [ ] excluded\n")
            }
            try put(root, "no.txt", "- [ ] not markdown\n")
            try put(root, "outside/source.md", "- [ ] source\n")
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.md"), withDestinationURL: root.appendingPathComponent("outside/source.md"))
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked-folder"), withDestinationURL: root.appendingPathComponent("outside"))
            let tasks = try TaskStore(root: root).list()
            try expect(tasks.map(\.path) == ["allowed/note.md", "outside/source.md"], "only regular scoped markdown; exclusions and symlinks skipped")
        }
        print("PASS 3: recursive scope, exclusions, hidden folders, symlinks")
        try fixture { root in
            let original = "\u{FEFF}# 中文\r\n- [ ] same 🚀\r\n- [ ] same 🚀\r\nprose \t untouched\r\n* [X] done"
            try put(root, "note.md", original)
            let store = TaskStore(root: root)
            let task = try store.list()[1]
            let updated = try store.toggle(path: task.path, line: task.line, expectedLine: task.rawLine, checked: true)
            try expect(updated.count == 3 && !updated[0].checked && updated[1].checked, "duplicates addressed by line")
            let before = Array(original.utf8)
            let after = Array(try Data(contentsOf: root.appendingPathComponent("note.md")))
            let differences = zip(before, after).filter { $0 != $1 }
            try expect(before.count == after.count && differences.count == 1 && differences[0].0 == 32 && differences[0].1 == 120, "only marker byte changed, including BOM/CRLF/Unicode and no final newline")
            _ = try store.toggle(path: updated[1].path, line: updated[1].line, expectedLine: updated[1].rawLine, checked: false)
            try expect(tryBytes(root, "note.md") == Data(original.utf8), "uncheck restores exact bytes")
            let done = try store.list()[2]
            _ = try store.toggle(path: done.path, line: done.line, expectedLine: done.rawLine, checked: false)
            try expect(tryBytes(root, "note.md") == Data(original.replacingOccurrences(of: "[X]", with: "[ ]").utf8), "uppercase checked marker can uncheck")
        }
        print("PASS 4: toggle/readback, duplicate lines, exact byte preservation, check/uncheck")
        try fixture { root in
            try put(root, "note.md", "- [ ] original\nprose\n")
            let store = TaskStore(root: root)
            let task = try store.list()[0]
            try put(root, "note.md", "- [ ] external edit\nnew prose\n")
            let external = tryBytes(root, "note.md")
            try expectFailure("stale line must fail") { _ = try store.toggle(path: task.path, line: task.line, expectedLine: task.rawLine, checked: true) }
            try expect(tryBytes(root, "note.md") == external, "stale toggle did not write")
            try put(root, "note.md", "- [ ] original\nexternal unrelated edit\n")
            try put(root, "new.md", "- [ ] freshly added\n")
            let updated = try store.toggle(path: task.path, line: task.line, expectedLine: task.rawLine, checked: true)
            try expect(updated.map(\.path) == ["new.md", "note.md"], "readback lists fresh files")
            try expect(tryBytes(root, "note.md") == Data("- [x] original\nexternal unrelated edit\n".utf8), "external unrelated edit preserved")
            let safe = tryBytes(root, "note.md")
            for line in [-1, 1, 999] {
                try expectFailure("non-task or invalid line must fail") { _ = try store.toggle(path: "note.md", line: line, expectedLine: "external unrelated edit", checked: true) }
            }
            try expect(tryBytes(root, "note.md") == safe, "invalid lines never write")
        }
        print("PASS 5: stale conflicts, external edits, fresh readback, invalid line indices")
        try fixture { root in
            try fixture { outside in
                try put(root, "note.md", "- [ ] safe\n")
                try put(root, "note.txt", "- [ ] text\n")
                try put(root, "templates/note.md", "- [ ] hidden\n")
                try put(root, ".hidden.md", "- [ ] hidden\n")
                try put(outside, "escape.md", "- [ ] outside\n")
                try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape.md"), withDestinationURL: outside.appendingPathComponent("escape.md"))
                try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("dir"), withDestinationURL: outside)
                let store = TaskStore(root: root)
                for path in ["../escape.md", "note.md/../note.md", "/etc/escape.md", root.appendingPathComponent("note.md").path, "./note.md", "note.txt", "templates/note.md", ".hidden.md", "escape.md", "dir/escape.md", "note.md\u{0}", "", "//note.md"] {
                    try expectFailure("unsafe path must fail: \(path)") { _ = try store.toggle(path: path, line: 0, expectedLine: "- [ ] safe", checked: true) }
                }
                try expect(tryBytes(root, "note.md") == Data("- [ ] safe\n".utf8), "safe file untouched")
                try expect(tryBytes(outside, "escape.md") == Data("- [ ] outside\n".utf8), "symlink target untouched")
                let listed = try store.list()
                try expect(listed.map(\.path) == ["note.md"], "escaping symlinks absent from list")
            }
        }
        print("PASS 6: malicious paths, non-markdown/excluded writes, symlink escape protection")
        try fixture { root in
            try put(root, "note.md", "- [ ] caf\u{00E9}\n")
            let store = TaskStore(root: root)
            let task = try store.list()[0]
            try put(root, "note.md", "- [ ] cafe\u{0301}\n")
            let external = tryBytes(root, "note.md")
            try expectFailure("canonically equal but byte-different expectedLine must conflict") { _ = try store.toggle(path: task.path, line: task.line, expectedLine: task.rawLine, checked: true) }
            try expect(tryBytes(root, "note.md") == external, "Unicode stale conflict leaves bytes untouched")
        }
        print("PASS 7: byte-exact Unicode stale conflict")
        try fixture { root in
            let lines = (0..<24).map { "- [ ] task \($0)" }
            try put(root, "note.md", lines.joined(separator: "\n") + "\n")
            let store = TaskStore(root: root)
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 8
            let errorLock = NSLock()
            var errors: [String] = []
            for (line, raw) in lines.enumerated() {
                queue.addOperation {
                    do { _ = try store.toggle(path: "note.md", line: line, expectedLine: raw, checked: true) }
                    catch {
                        errorLock.lock()
                        errors.append(String(describing: error))
                        errorLock.unlock()
                    }
                }
            }
            queue.waitUntilAllOperationsAreFinished()
            let tasks = try store.list()
            try expect(errors.isEmpty && tasks.count == 24 && tasks.allSatisfy(\.checked), "serialized concurrent toggles must retain all changes")
            try expect(tryBytes(root, "note.md") == Data((lines.map { $0.replacingOccurrences(of: "[ ]", with: "[x]") }.joined(separator: "\n") + "\n").utf8), "concurrent toggles preserve exact remaining bytes")
        }
        print("PASS 8: serial locking under 24 concurrent toggles")
        try fixture { root in
            try expectFailure("missing vault must report load error, not empty tasks") { _ = try TaskStore(root: root.appendingPathComponent("missing")).list() }
            try put(root, "not-directory.md", "plain text")
            try expectFailure("non-directory vault must report load error") { _ = try TaskStore(root: root.appendingPathComponent("not-directory.md")).list() }
            let empty = try TaskStore(root: root).list()
            try expect(empty.isEmpty, "real empty vault returns no tasks")
        }
        print("PASS 9: distinguish inaccessible source from empty checklist")
    }
}
