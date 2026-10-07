import AppKit
import SwiftUI
import IOKit

enum SleepSetting {
    static func read() -> Bool? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        return (IORegistryEntryCreateCFProperty(entry, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.boolValue
    }

    static func script(_ enabled: Bool) -> String {
        "do shell script \"/usr/bin/pmset -a disablesleep \(enabled ? 1 : 0)\" with administrator privileges"
    }
}

@MainActor final class Controller: ObservableObject {
    @Published var enabled: Bool? = SleepSetting.read()
    @Published var busy = false
    @Published var error: String?
    weak var panel: NSPanel?
    var dragOrigin: NSPoint?
    var changed: (() -> Void)?

    func refresh() {
        enabled = SleepSetting.read()
        changed?()
    }

    func set(_ value: Bool, completion: (() -> Void)? = nil) {
        guard !busy else { return }
        busy = true
        error = nil
        // Only fixed commands reach the privileged shell; no user text is interpolated.
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", SleepSetting.script(value)]
            let pipe = Pipe()
            process.standardError = pipe
            do {
                try process.run()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                process.waitUntilExit()
                let status = process.terminationStatus
                DispatchQueue.main.async {
                    self.busy = false
                    self.refresh()
                    if status != 0 {
                        self.error = output.contains("-128") ? "Cancelled. Sleep setting unchanged." : "macOS could not change sleep: \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
                    } else if self.enabled != value {
                        self.error = "macOS did not confirm the change. Try again."
                    } else {
                        completion?()
                    }
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    self.busy = false
                    self.error = message
                }
            }
        }
    }

    func drag(_ value: DragGesture.Value) {
        guard let panel else { return }
        if dragOrigin == nil { dragOrigin = panel.frame.origin }
        guard let origin = dragOrigin, let screen = panel.screen else { return }
        let bounds = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: min(max(origin.x + value.translation.width, bounds.minX), bounds.maxX - panel.frame.width),
            y: min(max(origin.y - value.translation.height, bounds.minY), bounds.maxY - panel.frame.height)))
    }
}

struct Pill: View {
    @ObservedObject var controller: Controller
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: controller.enabled == true ? "sun.max.fill" : "moon.zzz.fill")
                    .font(.system(size: 25)).foregroundStyle(controller.enabled == true ? .orange : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Awake Pill").font(.system(size: 17, weight: .semibold))
                    Text(controller.enabled.map { $0 ? "Lid closed · apps keep running" : "Normal sleep is allowed" } ?? "Sleep status unavailable")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 5).onChanged(controller.drag).onEnded { _ in
                controller.dragOrigin = nil
                if let panel = controller.panel { UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: "origin") }
            })
            Button {
                controller.set(controller.enabled != true)
            } label: {
                HStack {
                    Image(systemName: controller.busy ? "hourglass" : "power")
                    Text(controller.busy ? "Waiting for macOS…" : controller.enabled == true ? "Allow sleep again" : "Keep awake with lid closed")
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(controller.enabled == true ? .gray : .orange)
            .disabled(controller.busy || controller.enabled == nil)
            Text(controller.error ?? "Keep the Mac ventilated, never in a closed bag. Uses more battery. Quit restores sleep; force quit does not.")
                .font(.system(size: 11)).foregroundStyle(controller.error == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20).frame(width: 350, height: 220, alignment: .topLeading)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 28))
        .background(RoundedRectangle(cornerRadius: 28).fill(.black.opacity(0.12)))
        .contextMenu { Button("Quit and restore sleep") { NSApp.terminate(nil) } }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in controller.refresh() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = Controller()
    var panel: NSPanel!
    var status: NSStatusItem!
    var toggleItem: NSMenuItem!
    var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 220), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: Pill(controller: controller))
        controller.panel = panel
        if let screen = NSScreen.main {
            var origin = NSPoint(x: screen.visibleFrame.maxX - 370, y: screen.visibleFrame.maxY - 340)
            if let saved = UserDefaults.standard.string(forKey: "origin") {
                let point = NSPointFromString(saved)
                if NSScreen.screens.contains(where: { $0.visibleFrame.contains(NSRect(origin: point, size: panel.frame.size)) }) { origin = point }
            }
            panel.setFrameOrigin(origin)
        }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show / hide Awake Pill", action: #selector(showPanel), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        toggleItem = NSMenuItem(title: "Keep awake", action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit and restore sleep", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        status.menu = menu
        controller.changed = { [weak self] in
            guard let self else { return }
            self.status.button?.image = NSImage(systemSymbolName: self.controller.enabled == true ? "sun.max.fill" : "moon.zzz", accessibilityDescription: "Awake Pill")
            self.status.button?.toolTip = self.controller.enabled == true ? "System sleep disabled" : "Normal sleep allowed"
            self.toggleItem.title = self.controller.enabled == true ? "Allow sleep again" : "Keep awake with lid closed"
            self.toggleItem.isEnabled = !self.controller.busy && self.controller.enabled != nil
        }
        controller.refresh()
        panel.orderFrontRegardless()
    }

    @objc func showPanel() { panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless() }
    @objc func toggle() { controller.set(controller.enabled != true) }
    @objc func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitting { return .terminateNow }
        guard !controller.busy else { panel.orderFrontRegardless(); return .terminateCancel }
        controller.refresh()
        if controller.enabled == false { return .terminateNow }
        panel.orderFrontRegardless()
        controller.set(false) { self.quitting = true; NSApp.terminate(nil) }
        return .terminateCancel
    }
}

@main struct AwakePillApp {
@MainActor static func main() {
if CommandLine.arguments.contains("--check") {
    precondition(SleepSetting.script(true) == "do shell script \"/usr/bin/pmset -a disablesleep 1\" with administrator privileges")
    precondition(SleepSetting.script(false) == "do shell script \"/usr/bin/pmset -a disablesleep 0\" with administrator privileges")
    guard let value = SleepSetting.read() else { fatalError("Cannot read kernel SleepDisabled") }
    print("Checks passed. Kernel SleepDisabled = \(value). No settings changed.")
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
}
}
