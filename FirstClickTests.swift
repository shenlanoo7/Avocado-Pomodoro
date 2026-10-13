import AppKit
import WebKit
@main struct FirstClickTests {
    static func main() {
        _ = NSApplication.shared
        let view = FirstClickWebView(frame: .zero, configuration: WKWebViewConfiguration())
        precondition(view.acceptsFirstMouse(for: nil), "inactive timer must accept initial mouse click")
        let content = view.hitTest(NSPoint(x: 0, y: 0))
        if let content { precondition(content.acceptsFirstMouse(for: nil), "WebKit hit-test target must receive initial click") }
        print("PASS inactive WKWebView and hit-test target accept first mouse")
    }
}
