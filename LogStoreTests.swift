import Foundation

func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !value() { throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main struct LogStoreTests {
    static func main() throws {
#if NATIVE_SHELL_TESTS
        let defaults = UserDefaults(suiteName:"pomodoro-fixed-size-tests")!
        defer { defaults.removePersistentDomain(forName:"pomodoro-fixed-size-tests") }
        for level in [0.4,0.5,0.65,1.0,-1.0,Double.nan] {
            try expect(NativeScale.normalized(level) == 0.65, "all size requests normalize to fixed 65 percent")
            defaults.set(level,forKey:NativeScale.defaultsKey)
            try expect(NativeScale.load(from:defaults) == 0.65,"old preferences do not change fixed size")
        }
        let frame = CGRect(x:100,y:200,width:380,height:580)
        let resized = NativeScale.frame(for:0.4,preserving:frame)
        try expect(abs(resized.width-247)<0.0001 && abs(resized.height-377)<0.0001,"fixed 65 percent window")
        try expect(resized.midX == frame.midX && resized.maxY == frame.maxY,"anchored geometry preserved")
        print("PASS fixed 65 percent native size, old preferences ignored and anchored geometry")
        let sequenceSource = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Main.swift"), encoding: .utf8)
        try expect(sequenceSource.contains("$('focusMinutes').value='42'") && sequenceSource.contains("timer.duration===2520") && sequenceSource.contains("42 min planned, 42:00 elapsed"), "native cycle QA selects custom minutes through setup and verifies custom native log")
        try expect(sequenceSource.contains("case \"loadTimerTasks\"") && sequenceSource.contains("receiveTimerTasks(") && sequenceSource.contains("--qa-picker"), "native read-only picker bridge and isolated QA exist")
        try expect(!sequenceSource.contains("EdgeDock") && !sequenceSource.contains("autoDock"), "native timer has no docking machinery")
        try expect(sequenceSource.contains("case \"hide\"") && sequenceSource.contains("window.orderOut(nil)"), "native hide route conceals timer without closing")
        try expect(sequenceSource.contains("--qa-visibility") && sequenceSource.contains("double click hides without moving timer") && sequenceSource.contains("hidden focus automatically reveals on muted expiry") && sequenceSource.contains("hidden rest automatically reveals on muted expiry"), "native visibility QA verifies hide and automatic reveal")
        print("PASS native hide/reveal QA and no docking")
        print("PASS read-only timer task picker native route and QA")
        try expect(!sequenceSource.contains("case \"setRestMinutes\":") && !sequenceSource.contains("case \"setSequence\":"), "rest and group editing bridges are removed")
        print("PASS custom native cycle QA input and log assertions")
        let earlyScript = AppDelegate.qaScript(early: true)
        try expect(earlyScript.contains("now-120000") && earlyScript.contains("timer.finish(now)"), "early QA finishes two-minute timer")
        let normalScript = AppDelegate.qaScript(early: false)
        try expect(normalScript.contains("now-1500001") && normalScript.contains("timer.tick(now)"), "normal QA preserves full timer completion")
        for script in [earlyScript, normalScript] {
            try expect(script.contains("persist(); render(); alarm();") && script.contains("getElementById('log').click()"), "QA uses real persistence, render, alarm, and log bridge")
        }
        print("PASS normal and early native QA scripts preserve real bridge flow")
#endif
        let base = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"]!).appendingPathComponent("pomodoro-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let earlyURL = base.appendingPathComponent("early.md")
        let earlyStore = LogStore(url: earlyURL, timeZone: TimeZone(secondsFromGMT: 0)!)
        let early = try JSONDecoder().decode(LogEntry.self, from: Data("""
        {"id":"early","name":"Read","note":"Two minutes","startedAt":0,"completedAt":120000,"elapsedSeconds":120,"endedEarly":true}
        """.utf8))
        try earlyStore.save(early)
        try expect(try String(contentsOf: earlyURL, encoding: .utf8) == "- [x] 1970-01-01 00:02 — 25 min planned, 02:00 elapsed — \"Read\" — completed\n  - Two minutes\n", "early finish appends actual active duration")
        print("PASS early finish appends actual 02:00 duration")
        try earlyStore.save(LogEntry(id: "paused", name: "Paused", note: "", startedAt: 0, completedAt: 600_000, elapsedSeconds: 120, endedEarly: true))
        try expect(try String(contentsOf: earlyURL, encoding: .utf8).contains("00:10 — 25 min planned, 02:00 elapsed"), "pause wall time greater than active duration is accepted")
        print("PASS paused early finish uses active duration")
        let custom = try JSONDecoder().decode(LogEntry.self, from: Data("""
        {"id":"custom","name":"Custom","note":"","startedAt":0,"completedAt":2520000,"elapsedSeconds":2520,"plannedSeconds":2520}
        """.utf8))
        try earlyStore.save(custom)
        try expect(try String(contentsOf: earlyURL, encoding: .utf8).contains("42 min planned, 42:00 elapsed"), "custom completion uses captured plan")
        print("PASS custom completion uses captured planned duration")
        for planned in [60, 10800] {
            try earlyStore.save(LogEntry(id:"limit-\(planned)", name:"Limit", note:"", startedAt:0, completedAt:Double(planned)*1000, elapsedSeconds:planned, plannedSeconds:planned))
            try earlyStore.save(LogEntry(id:"pause-\(planned)", name:"Pause", note:"", startedAt:0, completedAt:120000, elapsedSeconds:30, event:"pause", sessionId:"session", plannedSeconds:planned))
            try earlyStore.save(LogEntry(id:"early-\(planned)", name:"Early", note:"", startedAt:0, completedAt:0, elapsedSeconds:0, endedEarly:true, plannedSeconds:planned))
        }
        for (i, values) in [(59,59,59000), (10860,0,0), (61,0,0), (2520,120,2520000), (2520,2520,2519999), (60,61,61000)].enumerated() {
            let (planned, elapsed, wall) = values
            var rejected = false
            do { try earlyStore.save(LogEntry(id:"bad-custom-\(i)", name:"Bad", note:"", startedAt:0, completedAt:Double(wall), elapsedSeconds:elapsed, plannedSeconds:planned)) } catch { rejected = true }
            try expect(rejected,"reject corrupt custom plan/completion \(i)")
        }
        print("PASS custom plan limits, pause/zero-early and corrupt/full completion validation")
        let beforeInvalid = try Data(contentsOf: earlyURL)
        for invalid in [
            LogEntry(id: "negative-duration", name: "x", note: "", startedAt: 0, completedAt: 120_000, elapsedSeconds: -1, endedEarly: true),
            LogEntry(id: "over-plan", name: "x", note: "", startedAt: 0, completedAt: 2_000_000, elapsedSeconds: 1501, endedEarly: true),
            LogEntry(id: "over-wall", name: "x", note: "", startedAt: 0, completedAt: 120_000, elapsedSeconds: 122, endedEarly: true),
            LogEntry(id: "normal-negative-duration", name: "x", note: "", startedAt: 0, completedAt: 1_500_000, elapsedSeconds: -1),
            LogEntry(id: "normal-over-plan", name: "x", note: "", startedAt: 0, completedAt: 1_500_000, elapsedSeconds: 1501),
            LogEntry(id: "missing-duration", name: "x", note: "", startedAt: 0, completedAt: 120_000, endedEarly: true),
            LogEntry(id: "backward", name: "x", note: "", startedAt: 120_000, completedAt: 0, elapsedSeconds: 0, endedEarly: true),
            LogEntry(id: "negative-start", name: "x", note: "", startedAt: -1, completedAt: 120_000, elapsedSeconds: 120, endedEarly: true),
            LogEntry(id: "infinite-end", name: "x", note: "", startedAt: 0, completedAt: .infinity, elapsedSeconds: 120, endedEarly: true),
            LogEntry(id: "out-of-range-end", name: "x", note: "", startedAt: 0, completedAt: 253_402_300_799_001, elapsedSeconds: 120, endedEarly: true),
            LogEntry(id: "short-normal-explicit", name: "x", note: "", startedAt: 0, completedAt: 120_000, elapsedSeconds: 120, endedEarly: false)
        ] {
            var rejected = false
            do { try earlyStore.save(invalid) } catch { rejected = true }
            try expect(rejected, "reject invalid duration/timestamps \(invalid.id)")
        }
        try expect(try Data(contentsOf: earlyURL) == beforeInvalid, "invalid explicit duration leaves log unchanged")
        print("PASS invalid explicit durations and early timestamps rejected")
        try earlyStore.save(LogEntry(id: "tolerance", name: "Tolerance", note: "", startedAt: 0, completedAt: 119_000, elapsedSeconds: 120, endedEarly: true))
        try earlyStore.save(LogEntry(id: "zero", name: "Zero", note: "", startedAt: 0, completedAt: 0, elapsedSeconds: 0, endedEarly: true))
        print("PASS one-second tolerance and zero-duration early finish")
        let url = base.appendingPathComponent("nested/log.md")
        let store = LogStore(url: url, timeZone: TimeZone(secondsFromGMT: 0)!)
        let entry = LogEntry(id: "one", name: "Read", note: "", startedAt: 0, completedAt: 1_500_000)
        try store.save(entry)
        let actual = try String(contentsOf: url, encoding: .utf8)
        try expect(actual == "- [x] 1970-01-01 00:25 — 25 min planned, 25:00 elapsed — \"Read\" — completed\n", "exact Markdown format and nested directory creation")
        print("PASS exact Markdown format and nested directory creation")
        let preserved = "# Existing notes\nExisting text without newline"
        try Data(preserved.utf8).write(to: url)
        try store.save(LogEntry(id: "two", name: "Write", note: "First note\nSecond note", startedAt: 0, completedAt: 1_500_000))
        let appended = try String(contentsOf: url, encoding: .utf8)
        try expect(appended == preserved + "\n- [x] 1970-01-01 00:25 — 25 min planned, 25:00 elapsed — \"Write\" — completed\n  - First note\n  - Second note\n", "append preserves existing content and nested notes")
        print("PASS append preserves existing content and nested notes")
        for entry in [
            LogEntry(id: "short", name: "x", note: "", startedAt: 0, completedAt: 1_499_999),
            LogEntry(id: "nan", name: "x", note: "", startedAt: .nan, completedAt: 1_500_000),
            LogEntry(id: "", name: "x", note: "", startedAt: 0, completedAt: 1_500_000),
            LogEntry(id: "blank", name: "  \n", note: "", startedAt: 0, completedAt: 1_500_000)
        ] {
            var rejected = false
            do { try store.save(entry) } catch { rejected = true }
            try expect(rejected, "reject invalid entry \(entry.id)")
        }
        try expect(try String(contentsOf: url, encoding: .utf8) == appended, "invalid entries leave log unchanged")
        print("PASS validation leaves log unchanged")
        let duplicate = LogEntry(id: "two", name: "Write", note: "First note\nSecond note", startedAt: 0, completedAt: 1_500_000)
        try LogStore(url: url, timeZone: TimeZone(secondsFromGMT: 0)!).save(duplicate)
        try expect(try String(contentsOf: url, encoding: .utf8) == appended, "durable duplicate prevention across store instances")
        print("PASS durable duplicate prevention")
        let recoveryURL = base.appendingPathComponent("recovery.md")
        let recoveryData = Data("existing\ncompleted\n".utf8)
        try recoveryData.write(to: recoveryURL)
        let pending: [String: Any] = ["ids": [], "pending": ["id": "recover", "before": Data("existing\n".utf8).base64EncodedString(), "after": recoveryData.base64EncodedString()]]
        try JSONSerialization.data(withJSONObject: pending).write(to: recoveryURL.appendingPathExtension("state.json"))
        try LogStore(url: recoveryURL).save(LogEntry(id: "recover", name: "Read", note: "", startedAt: 0, completedAt: 1_500_000))
        try expect(try Data(contentsOf: recoveryURL) == recoveryData, "recover interrupted commit without duplicate")
        print("PASS interrupted commit recovery")
        let escapedURL = base.appendingPathComponent("escaped.md")
        try LogStore(url: escapedURL, timeZone: TimeZone(secondsFromGMT: 0)!).save(LogEntry(id: "escaped", name: "Read \"book\"\nnext", note: "", startedAt: 0, completedAt: 1_507_000))
        try expect(try String(contentsOf: escapedURL, encoding: .utf8) == "- [x] 1970-01-01 00:25 — 25 min planned, 25:00 elapsed — \"Read \\\"book\\\" next\" — completed\n", "escape quotes, flatten title, record fixed active time")
        print("PASS safe title and fixed active time despite longer wall time")
        let concurrentURL = base.appendingPathComponent("concurrent.md")
        let errors = NSMutableArray(), errorLock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 24) { i in
            do { try LogStore(url: concurrentURL).save(LogEntry(id: "parallel-\(i)", name: "parallel", note: "", startedAt: 0, completedAt: 1_500_000)) }
            catch { errorLock.lock(); errors.add(error); errorLock.unlock() }
        }
        try expect(errors.count == 0, "concurrent saves succeed")
        let concurrentLines = try String(contentsOf: concurrentURL, encoding: .utf8).split(separator: "\n")
        try expect(concurrentLines.count == 24, "concurrent writers preserve all entries")
        print("PASS concurrent saves preserve all entries")
    }
}
