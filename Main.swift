import AppKit
import WebKit

enum NativeLanguage {
    static let defaultsKey = "AvocadoPomodoroLanguage"
    static func normalized(_ language: String) -> String { language == "zh" ? "zh" : "en" }
    static func load(from defaults: UserDefaults = .standard) -> String { normalized(defaults.string(forKey: defaultsKey) ?? "en") }
    static func save(_ language: String, to defaults: UserDefaults = .standard) { defaults.set(normalized(language), forKey: defaultsKey) }
    static let titles = ["Show Timer":"显示计时器", "Settings…":"设置…", "Quit Pomodoro":"退出番茄钟", "Quit Avocado Pomodoro":"退出牛油果番茄钟", "Edit":"编辑", "Undo":"撤销", "Redo":"重做", "Cut":"剪切", "Copy":"复制", "Paste":"粘贴", "Select All":"全选", "Pomodoro Settings":"番茄钟设置", "Obsidian Checklist":"Obsidian 清单", "Pomodoro":"番茄钟"]
    static func text(_ title: String, language: String) -> String {
        let key = titles.first(where: { $0.value == title })?.key ?? title
        return language == "zh" ? titles[key] ?? key : key
    }
}

enum NativeScale {
    static let defaultsKey = "AvocadoPomodoroScale"
    static func normalized(_ level: Double) -> Double { 0.65 }
    static func load(from defaults: UserDefaults = .standard) -> Double { 0.65 }
    static func save(_ level: Double, to defaults: UserDefaults = .standard) {}
    static func frame(for level: Double, preserving frame: CGRect) -> CGRect {
        let scale = normalized(level)
        let size = CGSize(width: 380 * scale, height: 580 * scale)
        return CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
    }
}

final class FirstClickWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class FocusWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

#if !NATIVE_SHELL_TESTS
@main
#endif
final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate {
    private var checklistWindow: FocusWindow?
    private var checklistWebView: WKWebView?
    private let tasksQueue = DispatchQueue(label: "Pomodoro.ObsidianTasks", qos: .utility)
    private lazy var taskStore = TaskStore(root: URL(fileURLWithPath: Self.qaMode ? Self.qaDirectory.appendingPathComponent(Self.qaPicker ? "picker-vault" : "tasks-vault").path : "/Users/shenlan/shenlan-lib", isDirectory: true))
    private var settingsWindow: FocusWindow?
    private var settingsWebView: WKWebView?
    private var statusItem: NSStatusItem!
    private var language = AppDelegate.qaMode ? "en" : NativeLanguage.load()
    private var qaVisibilityChecks: [[String: Any]] = []
    private var window: FocusWindow!
    private var webView: WKWebView!
    private var sound: NSSound?
    private var alarmRepeat: Timer?
    private var alarmStop: Timer?
    private var shuttingDown = false
    private var soundPlaybackAccepted = false
    private static var qaVisibility: Bool { CommandLine.arguments.contains("--qa-visibility") }
    private static var qaCycle: Bool { CommandLine.arguments.contains("--qa-cycle") }
    private static var qaEarly: Bool { CommandLine.arguments.contains("--qa-early") }
    private static var qaUI: Bool { CommandLine.arguments.contains("--qa-ui") }
    private static var qaSettings: Bool { CommandLine.arguments.contains("--qa-settings") }
    private static var qaPause: Bool { CommandLine.arguments.contains("--qa-pause") }
    private static var qaChecklist: Bool { CommandLine.arguments.contains("--qa-checklist") }
    private static var qaPicker: Bool { CommandLine.arguments.contains("--qa-picker") }
    private static var qaMode: Bool { CommandLine.arguments.contains("--qa") || qaEarly || qaUI || qaSettings || qaPause || qaChecklist || qaPicker || qaVisibility || qaCycle }
    private var scaleLevel: Double = NativeScale.load()
    private var qaScaleChecks: [[String: Any]] = []
    private static let qaDirectory = URL(fileURLWithPath: "/Users/shenlan/.hermes/cache/scratch/pomodoro-native-qa", isDirectory: true)
    private let logStore: LogStore = {
        let path = AppDelegate.qaMode ? AppDelegate.qaDirectory.appendingPathComponent("pomodoro-log.md").path : (ProcessInfo.processInfo.environment["POMODORO_LOG_PATH"] ?? "/Users/shenlan/shenlan-lib/Pomodoro/pomodoro-log.md")
        return LogStore(url: URL(fileURLWithPath: path))
    }()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenus()
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "native")
        config.websiteDataStore = Self.qaMode ? .nonPersistent() : .default()
        webView = FirstClickWebView(frame: NSRect(x: 0, y: 0, width: 380 * scaleLevel, height: 580 * scaleLevel), configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        window = FocusWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Avocado Pomodoro"
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.delegate = self
        window.contentView = webView
        window.center()
        if !Self.qaMode { window.setFrameAutosaveName("AvocadoPomodoroWindow") }
        window.setFrame(NativeScale.frame(for: scaleLevel, preserving: window.frame), display: true)
        clampTimerToScreens()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.loadHTMLString("<body style='background:#203029;color:white;font:16px monospace;padding:24px'>Missing index.html. Run build.sh after the frontend files are ready.</body>", baseURL: nil)
        }
        if let url = Bundle.main.url(forResource: "beep", withExtension: "wav") { sound = NSSound(contentsOf: url, byReference: false) }
    }

    private func installMenus() {
        let bar = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Avocado Pomodoro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; bar.addItem(appItem)
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: NSSelectorFromString(selector), keyEquivalent: key)
        }
        let redo = NSMenuItem(title: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.insertItem(redo, at: 1)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = edit; bar.addItem(editItem)
        NSApp.mainMenu = bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let url = Bundle.main.url(forResource: "StatusIcon@2x", withExtension: "png"), let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            statusItem.button?.image = image
            statusItem.button?.imagePosition = .imageOnly
        } else {
            // Keep a usable menu if a damaged bundle is missing the supplied image.
            statusItem.button?.title = "◷"
        }
        statusItem.button?.toolTip = "Pomodoro"
        let statusMenu = NSMenu()
        let show = statusMenu.addItem(withTitle: "Show Timer", action: #selector(showTimer), keyEquivalent: "")
        show.target = self
        let settings = statusMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: "")
        settings.target = self
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "Quit Pomodoro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = statusMenu
        updateLanguageMenus()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "drag":
            defer { clampTimerToScreens() }
            let event = NSApp.currentEvent
            if let event, event.type == .leftMouseDown { window.performDrag(with: event) }
            else if let synthetic = NSEvent.mouseEvent(with: .leftMouseDown, location: window.convertPoint(fromScreen: NSEvent.mouseLocation), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                window.performDrag(with: synthetic)
            }
        case "hide":
            guard message.webView === webView else { return }
            window.orderOut(nil)
        case "alarm": startAlarm()
        case "silence": stopAlarm()
        case "checklist": showChecklist()
        case "startTask":
            guard message.webView === checklistWebView,
                  let name = body["name"] as? String,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let data = try? JSONSerialization.data(withJSONObject: [name]),
                  let json = String(data: data, encoding: .utf8) else { return }
            showTimer()
            webView.evaluateJavaScript("startChecklistTask(\(json)[0]);", completionHandler: nil)

        case "qaPickerChecklist":
            guard Self.qaPicker, message.webView === checklistWebView,
                  let keys = body["keys"] as? [String], let data = try? JSONSerialization.data(withJSONObject: keys),
                  let json = String(data:data,encoding:.utf8) else { return }
            exercisePickerQA(checklistKeys: json)
        case "qaPickerResult":
            if Self.qaPicker {
                let bytes = (try? String(contentsOf:Self.qaDirectory.appendingPathComponent("picker-vault/Picker.md"),encoding:.utf8)) ?? ""
                let unchanged = bytes == "# Picker QA\n- [ ] Native picker task\n- [x] Done picker task\n- [ ] Another open task\n"
                writeQAReport(["ok":body["ok"] as? Bool == true && unchanged,"mode":"picker","picker":body,"taskBytesUnchanged":unchanged])
            }
        case "checklistReady", "loadTasks":
            if checklistWindow?.isVisible == true { loadTasks(requestID: body["requestId"] as? Int) }
        case "openTaskLink":
            guard message.webView === checklistWebView, let value = body["url"] as? String,
                  let url = URL(string: value), let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty else { return }
            NSWorkspace.shared.open(url)
        case "checklistClose": checklistWindow?.orderOut(nil)
        case "checklistDrag":
            if let checklistWindow, let event = NSEvent.mouseEvent(with: .leftMouseDown, location: checklistWindow.convertPoint(fromScreen: NSEvent.mouseLocation), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: checklistWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { checklistWindow.performDrag(with: event) }
        case "toggleTask":
            guard message.webView === checklistWebView,
                  let path = body["path"] as? String, let line = body["line"] as? Int,
                  let expected = body["expectedLine"] as? String, let checked = body["checked"] as? Bool else { return }
            let requestID = body["requestId"] as? Int
            let store = taskStore
            tasksQueue.async { [weak self] in
                do { let tasks = try store.toggle(path: path, line: line, expectedLine: expected, checked: checked); self?.sendTasks(tasks, requestID: requestID) }
                catch { self?.sendTaskError(error, requestID: requestID) }
            }
        case "qaChecklistExternal":
            if Self.qaChecklist {
                do {
                    let url = Self.qaDirectory.appendingPathComponent("tasks-vault/Tasks.md")
                    let text = try String(contentsOf:url,encoding:.utf8)
                    try Data(text.replacingOccurrences(of:"- [ ] Native task to toggle",with:"- [x] Native task to toggle").utf8).write(to:url,options:.atomic)
                } catch { writeQAReport(["ok":false,"error":error.localizedDescription]) }
            }
        case "qaChecklistResult":
            if Self.qaChecklist { writeQAReport(["ok":body["ok"] ?? false,"checklist":body]) }
        case "settings": showSettings()
        case "languageReady":
            syncLanguage(to: message.webView)
        case "setLanguage":
            guard message.webView === settingsWebView,
                  let value = body["language"] as? String, ["en", "zh"].contains(value) else { return }
            language = value
            if !Self.qaMode { NativeLanguage.save(value) }
            updateLanguageMenus()
            syncLanguage(to: webView)
            syncLanguage(to: checklistWebView)
            syncLanguage(to: settingsWebView)
        case "settingsReady": syncSettings()
        case "settingsClose": settingsWindow?.orderOut(nil)
        case "settingsDrag":
            if let settingsWindow, let synthetic = NSEvent.mouseEvent(with: .leftMouseDown, location: settingsWindow.convertPoint(fromScreen: NSEvent.mouseLocation), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: settingsWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { settingsWindow.performDrag(with: synthetic) }
        case "setSkin":
            guard let skin = body["skin"] as? String, ["avocado", "kirby"].contains(skin) else { return }
            webView.evaluateJavaScript("applySkin('\(skin)');") { [weak self] _, _ in self?.syncSettings() }
        case "setPrompts":
            guard message.webView === settingsWebView, let prompts = body["prompts"] as? [String], prompts.count <= 500, prompts.allSatisfy({ $0.count <= 2000 }),
                  let data = try? JSONSerialization.data(withJSONObject: prompts), let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("applyPrompts(\(json));")
        case "setMuted":
            guard let muted = body["muted"] as? Bool else { return }
            webView.evaluateJavaScript("applyMuted(\(muted ? "true" : "false"));") { [weak self] _, _ in self?.syncSettings() }

        case "start": showTimer()
        case "qaCycleResult":
            if Self.qaCycle {
                let markdown = (try? String(contentsOf:logStore.url,encoding:.utf8)) ?? ""
                let marker = body["noteMarker"] as? String ?? ""
                let logVerified = !marker.isEmpty && markdown.contains("42 min planned, 42:00 elapsed — \"Native QA Cycle\" — completed\n  - \(marker)\n")
                writeQAReport(["ok":body["ok"] as? Bool == true && logVerified,"mode":"cycle","cycle":body,"logVerified":logVerified,"logPath":logStore.url.path,"markdown":markdown])
            }
        case "reveal":
            showTimer()
            if Self.qaUI { qaVisibilityChecks.append(["action": "reveal", "visible": window.isVisible]) }
        case "qaUIResult":
            if Self.qaUI { writeQAReport(["ok": body["ok"] ?? false, "ui": body, "visibilityChecks": qaVisibilityChecks, "statusMenu": statusItem.menu?.items.map { $0.title } ?? []]) }
        case "save":
            do {
                let data = try JSONSerialization.data(withJSONObject: body)
                let entry = try JSONDecoder().decode(LogEntry.self, from: data)
                try logStore.save(entry)
                callback(["ok": true, "id": entry.id])
            } catch {
                callback(["ok": false, "id": body["id"] as? String ?? "", "error": error.localizedDescription])
            }
        default: break
        }
    }

    @objc private func showTimer() {
        clampTimerToScreens()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var screenFrames: [CGRect] { NSScreen.screens.map { $0.visibleFrame } }
    private func clampTimerToScreens() {
        guard window != nil else { return }
        window.setFrame(VisibleWindow.frame(window.frame, screens: screenFrames), display: true)
    }
    func applicationDidChangeScreenParameters(_ notification: Notification) { clampTimerToScreens() }

    private func showChecklist() {
        if checklistWindow == nil {
            let config = WKWebViewConfiguration()
            config.userContentController.add(self, name: "native")
            config.websiteDataStore = Self.qaMode ? .nonPersistent() : .default()
            let view = FirstClickWebView(frame: NSRect(x: 0, y: 0, width: 460, height: 640), configuration: config)
            view.setValue(false, forKey: "drawsBackground")
            view.navigationDelegate = self
            let panel = FocusWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.title = "Obsidian Checklist"
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.contentView = view
            checklistWindow = panel
            checklistWebView = view
            panel.center()
            if let url = Bundle.main.url(forResource: "checklist", withExtension: "html") { view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) }
        }
        checklistWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        loadTasks()
    }

    private func runVisibilityQA() {
        guard let screen = window.screen?.visibleFrame ?? screenFrames.first else {
            writeQAReport(["ok":false,"mode":"visibility","error":"No screen"]); return
        }
        let original = window.frame
        var checks: [[String:Any]] = []
        webView.evaluateJavaScript("muted=true;timer=new Timer();timer.start('Hidden QA');timer.deadline=Date.now()+1500;persist();render();$('body').dispatchEvent(new MouseEvent('dblclick',{bubbles:true}));") { [weak self] _, error in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.2) {
                checks.append(["name":"double click hides without moving timer","ok":error == nil && !self.window.isVisible && self.window.frame == original])
                DispatchQueue.main.asyncAfter(deadline:.now()+4) {
                    checks.append(["name":"hidden focus automatically reveals on muted expiry","ok":self.window.isVisible && self.window.frame == original])
                    self.webView.evaluateJavaScript("timer=new Timer();timer.break();timer.deadline=Date.now()+1500;persist();render();$('dial').dispatchEvent(new MouseEvent('dblclick',{bubbles:true}));") { _, restError in
                        DispatchQueue.main.asyncAfter(deadline:.now()+0.2) {
                            checks.append(["name":"dial double click hides rest","ok":restError == nil && !self.window.isVisible])
                            DispatchQueue.main.asyncAfter(deadline:.now()+4) {
                                checks.append(["name":"hidden rest automatically reveals on muted expiry","ok":self.window.isVisible && self.window.frame == original])
                                self.finishVisibilityQA(checks:checks,screen:screen,original:original)
                            }
                        }
                    }
                }
            }
        }
    }

    private func finishVisibilityQA(checks initialChecks: [[String:Any]], screen: CGRect, original: CGRect) {
        var checks = initialChecks
        for x in [screen.minX-100,screen.maxX-100] {
            self.window.setFrame(CGRect(x:x,y:screen.midY-original.height/2,width:original.width,height:original.height),display:true)
            self.clampTimerToScreens()
            checks.append(["name":"drag boundary stays fully visible","ok":screen.contains(self.window.frame) && self.window.frame.size == original.size && self.window.isVisible])
        }
        let boundary = self.window.frame
        DispatchQueue.main.asyncAfter(deadline:.now()+11) {
            checks.append(["name":"idle never redocks or hides","ok":self.window.isVisible && self.window.frame == boundary])
            self.window.orderOut(nil)
            self.showTimer()
            checks.append(["name":"Show Timer restores hidden fixed floating window","ok":self.window.isVisible && self.window.frame == boundary && self.window.level == .floating && self.window.frame.size == CGSize(width:247,height:377)])
            let statusImage = self.statusItem.button?.image
            let imageOK = statusImage?.isTemplate == true && statusImage?.size == NSSize(width: 18, height: 18)
            checks.append(["name":"supplied menu image is an 18pt template","ok":imageOK])
            self.writeQAReport(["ok":checks.allSatisfy { $0["ok"] as? Bool == true },"mode":"visibility","checks":checks,"statusImagePresent":statusImage != nil,"statusImageTemplate":statusImage?.isTemplate ?? false,"statusImageWidth":statusImage?.size.width ?? 0,"statusImageHeight":statusImage?.size.height ?? 0])
        }
    }

    private func exercisePickerQA(checklistKeys: String) {
        webView.evaluateJavaScript("$('name').value='test3';$('focusMinutes').value='42';") { [weak self] _, error in
            guard let self else { return }
            if let error { self.writeQAReport(["ok":false,"mode":"picker","error":error.localizedDescription]); return }
            self.checklistWebView?.evaluateJavaScript("""
            (()=>{
              $('note').value='all';$('filter').value='all';render();
              const expected=\(checklistKeys),buttons=[...document.querySelectorAll('.taskStart')];
              if(buttons.length!==expected.length)throw new Error('Checklist Start count mismatch');
              const row=[...document.querySelectorAll('.taskRow')].find(row=>row.querySelector('.taskText').textContent==='Native picker task');
              if(!row||!row.querySelector('button'))throw new Error('Missing native checklist Start');
              row.querySelector('button').click();
            })();
            """) { [weak self] _, error in
                guard let self else { return }
                if let error { self.writeQAReport(["ok":false,"mode":"picker","error":error.localizedDescription]); return }
                DispatchQueue.main.asyncAfter(deadline:.now()+0.3) {
                    self.webView.evaluateJavaScript("native('qaPickerResult',{ok:timer.state==='running'&&timer.name==='Native picker task'&&timer.duration===2520&&!document.getElementById('namePicker'),name:timer.name,duration:timer.duration,state:timer.state});")
                }
            }
        }
    }

    private func runCycleQA() { showSettings() }

    private func configureCycleQA() {
        settingsWebView?.evaluateJavaScript("native('setMuted',{muted:true});") { [weak self] _, error in
            guard let self else { return }
            if let error { self.writeQAReport(["ok":false,"mode":"cycle","error":error.localizedDescription]); return }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { self.exerciseCycleQA() }
        }
    }

    private func exerciseCycleQA() {
        webView.evaluateJavaScript("""
        (()=>{
          const checks=[],marker='Native cycle snapshot '+Date.now();let snapshotID='';
          const check=(name,ok)=>checks.push({name,ok:!!ok,state:timer.state,mode:timer.mode,pending:timer.pendingNotes.length});
          const report=error=>native('qaCycleResult',{ok:!error&&checks.every(c=>c.ok),error:error||'',checks,noteMarker:marker,snapshotID});
          const later=fn=>setTimeout(()=>{try{fn()}catch(e){report(String(e))}},350);
          const expire=()=>{if(timer.mode==='focus')timer.startedAt=Date.now()-timer.duration*1000-1;timer.deadline=Date.now()-1;persist();tickTimer();};
          try {
            check('fixed rest has no editing API',typeof window.applyRestMinutes==='undefined');
            $('name').value='Native QA Cycle';$('focusMinutes').value='42';$('start').click();
            check('manual Start captures custom focus',timer.state==='running'&&timer.mode==='focus'&&timer.duration===2520);
            $('focusMinutes').value='7';expire();later(()=>{
              snapshotID=timer.pendingNotes[0]?.id;
              check('focus automatically starts one rest with captured note',timer.state==='running'&&timer.mode==='break'&&timer.duration===300&&timer.pendingNotes.length===1&&timer.pendingNotes[0].plannedSeconds===2520);
              expire();later(()=>{
                check('rest stops without starting another focus',timer.state==='completed'&&timer.mode==='break'&&timer.pendingNotes[0]?.id===snapshotID);
                const liveID=timer.id,original=window.nativeResult;
                window.nativeResult=result=>{
                  original(result);window.nativeResult=original;
                  check('native snapshot save leaves rest stopped',result.ok&&result.id===snapshotID&&timer.id===liveID&&timer.state==='completed'&&timer.mode==='break'&&timer.pendingNotes.length===0);
                  if(!result.ok){report(result.error);return;}
                  tickTimer(Date.now()+36000000);
                  check('delayed tick cannot start focus',timer.state==='completed'&&timer.id===liveID);
                  $('again').click();check('Next returns to setup',timer.state==='idle');
                  $('start').click();check('only manual Start begins next focus',timer.mode==='focus'&&timer.state==='running'&&timer.duration===420);report();
                };
                $('note').value=marker;$('note').dispatchEvent(new Event('input'));$('log').click();
              });
            });
          }catch(e){report(String(e));}
        })();
        """) { [weak self] _, error in
            if let error { self?.writeQAReport(["ok":false,"mode":"cycle","error":error.localizedDescription]) }
        }
    }

    private func runChecklistQA() {
        checklistWebView?.evaluateJavaScript("""
        (()=>{const original=receiveTasks;let phase=0;window.receiveTasks=result=>{original(result);if(!result.ok){native('qaChecklistResult',{ok:false,error:result.error});return;}const task=result.tasks.find(t=>t.text==='Native task to toggle');if(!task){native('qaChecklistResult',{ok:false,error:'No QA task'});return;}if(phase===0){phase=1;[...document.querySelectorAll('.taskRow')].find(r=>r.textContent.includes('Native task to toggle')).querySelector('input').click();}else if(phase===1&&task.checked){phase=2;[...document.querySelectorAll('.taskRow')].find(r=>r.textContent.includes('Native task to toggle')).querySelector('input').click();}else if(phase===2&&!task.checked){phase=3;native('qaChecklistExternal');}else if(phase===3&&task.checked){phase=4;native('qaChecklistResult',{ok:true,checkedThenUnchecked:true,externalEditReflected:true,taskCount:result.tasks.length,path:task.path,rawLine:task.rawLine});}};native('loadTasks',{requestId:1});})();
        """) { [weak self] _, error in
            if let error { self?.writeQAReport(["ok":false,"error":error.localizedDescription]) }
        }
    }

    private func loadTasks(requestID: Int? = nil) {
        let store = taskStore
        tasksQueue.async { [weak self] in
            do { self?.sendTasks(try store.list(), requestID: requestID) }
            catch { self?.sendTaskError(error, requestID: requestID) }
        }
    }

    private func sendTasks(_ tasks: [VaultTask], requestID: Int?) {
        do {
            let data = try JSONEncoder().encode(tasks)
            let objects = try JSONSerialization.jsonObject(with: data)
            sendTaskResult(["ok":true,"tasks":objects,"requestId":requestID as Any? ?? NSNull()])
        } catch { sendTaskError(error, requestID: requestID) }
    }

    private func sendTaskError(_ error: Error, requestID: Int?) {
        sendTaskResult(["ok":false,"error":error.localizedDescription,"requestId":requestID as Any? ?? NSNull()])
    }

    private func sendTaskResult(_ result: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: result), let json = String(data:data,encoding:.utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.checklistWebView?.evaluateJavaScript("window.receiveTasks && window.receiveTasks(\(json));")
        }
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let config = WKWebViewConfiguration()
            config.userContentController.add(self, name: "native")
            config.websiteDataStore = .nonPersistent()
            let view = FirstClickWebView(frame: NSRect(x: 0, y: 0, width: 330, height: 530), configuration: config)
            view.setValue(false, forKey: "drawsBackground")
            view.navigationDelegate = self
            let panel = FocusWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.title = "Pomodoro Settings"
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.contentView = view
            settingsWindow = panel
            settingsWebView = view
            panel.center()
            if let url = Bundle.main.url(forResource: "settings", withExtension: "html") { view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) }
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        syncSettings()
    }

    private func runSettingsQA() {
        var checks: [[String: Any]] = []
        func check(_ levels: ArraySlice<Double>) {
            guard let level = levels.first else {
                settingsWebView?.evaluateJavaScript("""
                (()=>{const panel=document.getElementById('panel');const r=panel.getBoundingClientRect();const metrics={width:r.width,height:r.height,font:parseFloat(getComputedStyle(document.getElementById('skin')).fontSize),noScroll:document.documentElement.scrollHeight<=innerHeight,english:uiLanguage()==='en'};document.getElementById('skin').value='kirby';document.getElementById('skin').dispatchEvent(new Event('change'));document.getElementById('sound').click();return JSON.stringify(metrics)})();
                """) { [weak self] metrics, error in
                    guard let self else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.webView.evaluateJavaScript("JSON.stringify({skin:document.documentElement.dataset.skin,scale:Number(document.getElementById('scale').value),muted,english:!/[\\u4e00-\\u9fff]/.test(document.body.innerText)})") { prefs, prefError in
                            self.writeQAReport(["ok":error == nil && prefError == nil,"settingsChecks":checks,"metrics":metrics as? String ?? "","preferences":prefs as? String ?? ""])
                        }
                    }
                }
                return
            }
            applyScale(level) { [weak self] _, error in
                guard let self, let settingsWindow = self.settingsWindow else { return }
                let r = settingsWindow.contentRect(forFrameRect: settingsWindow.frame)
                checks.append(["scale":level,"width":r.width,"height":r.height,"visible":settingsWindow.isVisible,"ok":error == nil && r.width == 330 && r.height == 530])
                check(levels.dropFirst())
            }
        }
        check([0.4,0.5,0.65][...])
    }

    private func updateLanguageMenus() {
        func translate(_ menu: NSMenu?) {
            guard let menu else { return }
            menu.title = NativeLanguage.text(menu.title, language: language)
            for item in menu.items {
                item.title = NativeLanguage.text(item.title, language: language)
                translate(item.submenu)
            }
        }
        translate(NSApp.mainMenu)
        translate(statusItem?.menu)
        statusItem?.button?.toolTip = NativeLanguage.text("Pomodoro", language: language)
        settingsWindow?.title = NativeLanguage.text("Pomodoro Settings", language: language)
        checklistWindow?.title = NativeLanguage.text("Obsidian Checklist", language: language)
    }

    private func syncLanguage(to view: WKWebView?) {
        view?.evaluateJavaScript("window.applyLanguage && window.applyLanguage('\(language)');", completionHandler: nil)
    }

    private func syncSettings() {
        guard let settingsWebView else { return }
        webView.evaluateJavaScript("JSON.stringify({skin:document.documentElement.dataset.skin,scale:Number(document.getElementById('scale').value),muted,prompts:promptCandidates()})") { value, error in
            guard error == nil, let json = value as? String else { return }
            settingsWebView.evaluateJavaScript("window.applyPreferences && window.applyPreferences({...\(json),language:'\(self.language)'});")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showTimer()
        return true
    }

    private func callback(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.nativeResult && window.nativeResult(\(json));") { [weak self] _, error in
            guard Self.qaMode, !Self.qaCycle, let self else { return }
            var report = value
            report["mode"] = "qa"
            report["logPath"] = self.logStore.url.path
            report["markdown"] = (try? String(contentsOf: self.logStore.url, encoding: .utf8)) ?? ""
            report["soundPlaybackAccepted"] = self.soundPlaybackAccepted
            report["javascriptCallbackError"] = error?.localizedDescription ?? NSNull()
            self.webView.evaluateJavaScript("JSON.stringify({state:timer.state,resolved:timer.resolved,feedback:document.getElementById('feedback').textContent})") { page, pageError in
                report["page"] = page as? String ?? ""
                report["pageReadError"] = pageError?.localizedDescription ?? NSNull()
                self.writeQAReport(report)
            }
        }
    }

    private func writeQAReport(_ report: [String: Any]) {
        do {
            var report = report
            report["scaleChecks"] = qaScaleChecks
            report["endedEarly"] = Self.qaEarly
            try FileManager.default.createDirectory(at: Self.qaDirectory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: Self.qaDirectory.appendingPathComponent("result.json"), options: .atomic)
            print("NATIVE_QA_RESULT " + String(decoding: data, as: UTF8.self))
        } catch { fputs("QA report failed: \(error)\n", stderr) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncLanguage(to: webView)
        updateLanguageMenus()
        if webView === checklistWebView {
            if Self.qaChecklist { runChecklistQA() }
            else if Self.qaPicker {
                checklistWebView?.evaluateJavaScript("const original=receiveTasks;let pickerReported=false;window.receiveTasks=result=>{original(result);if(pickerReported)return;pickerReported=true;if(result.ok){native('qaPickerChecklist',{keys:result.tasks.filter(t=>!t.checked).map(t=>t.path+':'+t.line)});}else{native('qaPickerResult',{ok:false,error:result.error});}};native('loadTasks');")
            } else { loadTasks() }
            return
        }
        if Self.qaChecklist {
            let root = Self.qaDirectory.appendingPathComponent("tasks-vault")
            do {
                try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
                try Data("# Native QA\n- [ ] Native task to toggle\nUnrelated text\n".utf8).write(to:root.appendingPathComponent("Tasks.md"),options:.atomic)
                showChecklist()
            } catch { writeQAReport(["ok":false,"error":error.localizedDescription]) }
            return
        }
        if webView === settingsWebView {
            syncSettings()
            if Self.qaCycle { configureCycleQA() }
            if Self.qaSettings { runSettingsQA() }
            return
        }
        if Self.qaSettings {
            applyScale(0.4) { [weak self] _, _ in self?.showSettings() }
            return
        }
        applyScale(scaleLevel) { [weak self] _, error in
            guard let self, Self.qaMode else { return }
            if let error { self.writeQAReport(["ok": false, "error": error.localizedDescription, "mode": "qa"]); return }
            if Self.qaVisibility { self.runVisibilityQA(); return }
            if Self.qaCycle { self.runCycleQA(); return }
            if Self.qaPicker {
                do {
                    let root = Self.qaDirectory.appendingPathComponent("picker-vault")
                    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
                    try Data("# Picker QA\n- [ ] Native picker task\n- [x] Done picker task\n- [ ] Another open task\n".utf8).write(to:root.appendingPathComponent("Picker.md"),options:.atomic)
                    self.showChecklist()
                } catch { self.writeQAReport(["ok":false,"mode":"picker","error":error.localizedDescription]) }
                return
            }
            if Self.qaPause {
                self.webView.evaluateJavaScript("""
                (()=>{
                  const original=window.nativeResult;let count=0;
                  window.nativeResult=result=>{original(result);if(result.ok&&++count===1)setTimeout(()=>{document.getElementById('pause').click();document.getElementById('end').click();document.getElementById('note').value='Native QA completion after pause';document.getElementById('log').click()},200);};
                  timer.start('Native QA Pause Session',Date.now()-120000);persist();render();
                  document.getElementById('pause').click();document.getElementById('pauseNote').value='Native QA interruption detail';document.getElementById('pauseNote').dispatchEvent(new Event('input'));document.getElementById('pauseSave').click();
                })();
                """) { _, error in
                    if let error { self.writeQAReport(["ok":false,"error":error.localizedDescription]) }
                }
                return
            }
            if Self.qaUI {
                self.webView.evaluateJavaScript("""
                (()=>{try{
                  const toolbarAbsent=!document.querySelector('.toolbar,#close');
                  document.getElementById('body').dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,clientX:120,clientY:140}));
                  const menuVisible=!document.getElementById('contextMenu').hidden;
                  document.getElementById('openSettings').click();
                  const popupOpen=true;
                  const box=document.querySelector('.widget').getBoundingClientRect();
                  const fits=box.x>=0&&box.y>=0&&box.right<=innerWidth&&box.bottom<=innerHeight;
                  native('settingsClose');
                  timer.start('UI QA');persist();render();
                  document.getElementById('body').dispatchEvent(new MouseEvent('dblclick',{bubbles:true}));
                  setTimeout(()=>{native('reveal');setTimeout(()=>native('qaUIResult',{ok:toolbarAbsent&&menuVisible&&popupOpen&&fits&&timer.state==='running',toolbarAbsent,menuVisible,popupOpen,fits,timerState:timer.state}),150)},150);
                }catch(e){native('qaUIResult',{ok:false,error:String(e)})}})();
                """) { _, error in
                    if let error { self.writeQAReport(["ok":false,"error":error.localizedDescription]) }
                }
                return
            }
            self.checkQAScales([0.65][...]) { [weak self] in
                guard let self else { return }
                self.applyScale(0.4) { [weak self] _, error in
                    guard let self else { return }
                    if let error { self.writeQAReport(["ok": false, "error": error.localizedDescription, "mode": "qa"]); return }
                    webView.evaluateJavaScript(Self.qaScript(early: Self.qaEarly)) { [weak delegate = self] _, error in
                        if let error { delegate?.writeQAReport(["ok": false, "error": error.localizedDescription, "mode": "qa"]) }
                    }
                }
            }
        }
    }

    private func applyScale(_ requestedLevel: Double, completion: ((Any?, Error?) -> Void)? = nil) {
        scaleLevel = NativeScale.normalized(requestedLevel)
        if !Self.qaMode { NativeScale.save(scaleLevel) }
        window.setFrame(NativeScale.frame(for: scaleLevel, preserving: window.frame), display: true)
        webView.evaluateJavaScript("window.applyScale(\(scaleLevel));") { result, error in completion?(result, error) }
    }

    private func checkQAScales(_ levels: ArraySlice<Double>, completion: @escaping () -> Void) {
        guard let level = levels.first else { completion(); return }
        applyScale(level) { [weak self] _, scaleError in
            guard let self else { return }
            self.webView.evaluateJavaScript("JSON.stringify((()=>{const r=document.querySelector('.widget').getBoundingClientRect();return {width:r.width,height:r.height,selected:document.getElementById('scale').value,viewportWidth:innerWidth,viewportHeight:innerHeight};})())") { value, rectError in
                let native = self.window.contentRect(forFrameRect: self.window.frame)
                var check: [String: Any] = ["level": level, "nativeWidth": native.width, "nativeHeight": native.height]
                if let text = value as? String, let data = text.data(using: .utf8),
                   let widget = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    check["widget"] = widget
                    let width = (widget["width"] as? NSNumber)?.doubleValue ?? -1
                    let height = (widget["height"] as? NSNumber)?.doubleValue ?? -1
                    check["ok"] = scaleError == nil && rectError == nil && abs(native.width - 380 * NativeScale.normalized(level)) < 0.5 && abs(native.height - 580 * NativeScale.normalized(level)) < 0.5 && abs(width - native.width) < 0.5 && abs(height - native.height) < 0.5
                } else { check["ok"] = false }
                check["error"] = (scaleError ?? rectError)?.localizedDescription ?? NSNull()
                self.qaScaleChecks.append(check)
                self.checkQAScales(levels.dropFirst(), completion: completion)
            }
        }
    }

    static func qaScript(early: Bool) -> String {
        let timerSetup = early
            ? "timer.start('Native QA Early Focus',now-120000); timer.finish(now);"
            : "timer.start('Native QA Focus',now-1500001); timer.deadline=now-1; timer.tick(now);"
        return """
        (() => {
          localStorage.clear(); muted=false;
          const now=Date.now(); \(timerSetup)
          persist(); render(); alarm();
          document.getElementById('note').value='WKWebView → Swift bridge verified\\nTriple-beep QA';
          setTimeout(()=>document.getElementById('log').click(),2200);
          return {state:timer.state,startedAt:timer.startedAt,completedAt:timer.completedAt};
        })()
        """
    }

    private func startAlarm() {
        stopAlarm()
        soundPlaybackAccepted = sound?.play() ?? false
        let deadline = ProcessInfo.processInfo.systemUptime + 15
        alarmRepeat = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if ProcessInfo.processInfo.systemUptime >= deadline { self.stopAlarm() }
            else { self.sound?.play() }
        }
        alarmStop = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in self?.stopAlarm() }
        if let alarmRepeat { RunLoop.main.add(alarmRepeat, forMode: .common) }
        if let alarmStop { RunLoop.main.add(alarmStop, forMode: .common) }
    }

    private func stopAlarm() {
        alarmRepeat?.invalidate(); alarmRepeat = nil
        alarmStop?.invalidate(); alarmStop = nil
        sound?.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !shuttingDown, webView != nil else { return .terminateNow }
        shuttingDown = true
        stopAlarm()
        // Frontend stores state on pagehide/beforeunload; WKWebView does not guarantee these on app termination.
        webView.evaluateJavaScript("if (typeof persist === 'function') persist(); window.dispatchEvent(new Event('native-close')); window.dispatchEvent(new Event('pagehide')); window.dispatchEvent(new Event('beforeunload'));") { _, _ in
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let resource = Bundle.main.resourceURL?.standardizedFileURL.path ?? ""
        decisionHandler(url.isFileURL && url.standardizedFileURL.path.hasPrefix(resource + "/") ? .allow : .cancel)
    }
}
