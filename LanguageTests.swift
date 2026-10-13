import Foundation

@main
struct LanguageTests {
    static func main() {
        let name = "PomodoroLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        precondition(NativeLanguage.load(from: defaults) == "en")
        NativeLanguage.save("zh", to: defaults)
        precondition(NativeLanguage.load(from: defaults) == "zh")
        NativeLanguage.save("invalid", to: defaults)
        precondition(NativeLanguage.load(from: defaults) == "en")
        precondition(NativeLanguage.text("Show Timer", language: "zh") == "显示计时器")
        precondition(NativeLanguage.text("显示计时器", language: "en") == "Show Timer")
        print("PASS native language defaults, persistence, normalization and menu switching")
    }
}
