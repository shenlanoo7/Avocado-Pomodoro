import Foundation
@main struct PauseLogTests {
 static func main() throws {
  let dir=URL(fileURLWithPath:ProcessInfo.processInfo.environment["TMPDIR"]!).appendingPathComponent("pause-log-\(UUID().uuidString)")
  defer {try? FileManager.default.removeItem(at:dir)}
  let url=dir.appendingPathComponent("log.md"),store=LogStore(url:url,timeZone:TimeZone(secondsFromGMT:0)!)
  let pause=LogEntry(id:"session-pause-1",name:"Research",note:"Interrupted by a call\nContinue with section two",startedAt:0,completedAt:120000,elapsedSeconds:120,endedEarly:nil,event:"pause",sessionId:"session")
  try store.save(pause);try store.save(pause)
  let text=try String(contentsOf:url,encoding:.utf8)
  precondition(text.contains("- [ ] 1970-01-01 00:02") && text.contains("— paused"))
  precondition(text == "- [ ] 1970-01-01 00:02 — 25 min planned, 02:00 elapsed — \"Research\" — paused\n  - Interrupted by a call\n  - Continue with section two\n")
  precondition(text.components(separatedBy:"— paused").count==2)
  precondition(!text.contains("— completed"))
  let done=LogEntry(id:"session",name:"Research",note:"Finished",startedAt:0,completedAt:1600000,elapsedSeconds:1500,endedEarly:false,event:"completed",sessionId:"session")
  try store.save(done)
  let final=try String(contentsOf:url,encoding:.utf8)
  precondition(final == text + "- [x] 1970-01-01 00:26 — 25 min planned, 25:00 elapsed — \"Research\" — completed\n  - Finished\n")
  do {try store.save(LogEntry(id:"bad",name:"Research",note:"",startedAt:0,completedAt:1000,elapsedSeconds:120,endedEarly:nil,event:"pause",sessionId:"session"));fatalError("invalid pause accepted")}catch{}
  print("PASS unified concise pause/completion format, active duration, durable dedupe and later completion")
 }
}
