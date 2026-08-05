import SwiftUI
import AppKit
import Combine

@MainActor
final class PanelState: ObservableObject {
    @Published var isDetached = false
}

private struct DismissPanelKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var dismissPanel: @MainActor () -> Void {
        get { self[DismissPanelKey.self] }
        set { self[DismissPanelKey.self] = newValue }
    }
}

final class LimonPanel: NSPanel {
    let panelState = PanelState()

    private weak var hosting: NSView?
    private var anchorTopLeft = NSPoint.zero
    private var trafficAnchor: NSPoint?
    private(set) var isRepositioning = false

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }

    func setContent<Content: View>(_ view: Content) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.safeAreaRegions = []

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 16
            glass.contentView = hostingView
            backgroundColor = .clear
            isOpaque = false
            contentView = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            contentView = effect
            hostingView.frame = effect.bounds
            hostingView.autoresizingMask = [.width, .height]
            effect.addSubview(hostingView)
        }
        hosting = hostingView
    }

    var preferredSize: NSSize {
        hosting?.fittingSize ?? NSSize(width: 320, height: 400)
    }

    func place(topLeft: NSPoint, size: NSSize) {
        anchorTopLeft = topLeft
        isRepositioning = true
        setFrame(NSRect(x: topLeft.x, y: topLeft.y - size.height,
                        width: size.width, height: size.height),
                 display: true)
        isRepositioning = false
    }

    func resizeContent(to size: CGSize) {
        guard size.width > 0, size.height > 0, size != frame.size else { return }
        place(topLeft: anchorTopLeft, size: NSSize(width: size.width, height: size.height))
    }

    func noteUserMovement() -> Bool {
        if isRepositioning { return false }
        anchorTopLeft = NSPoint(x: frame.minX, y: frame.maxY)
        return true
    }

    func snapBack(to origin: NSPoint) {
        isRepositioning = true
        anchorTopLeft = NSPoint(x: origin.x, y: origin.y + frame.height)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(NSRect(origin: origin, size: frame.size), display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.isRepositioning = false }
        })
    }

    func markDetached() {
        panelState.isDetached = true
        for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton] {
            guard let button = standardWindowButton(buttonType) else { continue }
            button.isHidden = false
            button.alphaValue = 0
            button.animator().alphaValue = 1
        }
        repositionTrafficLights()
    }

    func completeDetach(alwaysOnTop: Bool) {
        styleMask.remove(.nonactivatingPanel)
        isFloatingPanel = false
        applyLevel(alwaysOnTop: alwaysOnTop)
    }

    func repositionTrafficLights() {
        guard panelState.isDetached,
              let close = standardWindowButton(.closeButton) else { return }
        if trafficAnchor == nil { trafficAnchor = close.frame.origin }
        guard let anchor = trafficAnchor else { return }

        let downward: CGFloat = close.superview?.isFlipped == true ? 3 : -3
        let buttons = [close, standardWindowButton(.miniaturizeButton)].compactMap { $0 }
        for (index, button) in buttons.enumerated() {
            button.setFrameOrigin(NSPoint(x: anchor.x + 20 * CGFloat(index),
                                          y: anchor.y + downward))
        }
    }

    func applyLevel(alwaysOnTop: Bool) {
        guard panelState.isDetached else { return }
        level = alwaysOnTop ? .floating : .normal
        collectionBehavior = alwaysOnTop ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.managed]
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let service: ColimaService
    private let statusItem: NSStatusItem
    private var attachedPanel: LimonPanel?
    private var detachedPanels: [LimonPanel] = []
    private var eventMonitors: [Any] = []
    private var clickMonitor: Any?
    private var titleSink: AnyCancellable?
    private var defaultsObserver: Any?
    private var dragTracker: Task<Void, Never>?

    private static let tearOffDistance: CGFloat = 40

    private var alwaysOnTop: Bool {
        UserDefaults.standard.bool(forKey: "alwaysOnTop")
    }

    init(service: ColimaService) {
        self.service = service
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let buttonWindow = self.statusItem.button?.window,
                      event.window === buttonWindow,
                      !event.modifierFlags.contains(.command) else { return event }
                self.statusClicked()
                return nil
            }
        }
        updateTitle()

        titleSink = service.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for panel in self.detachedPanels { panel.applyLevel(alwaysOnTop: self.alwaysOnTop) }
            }
        }
    }

    private func updateTitle() {
        statusItem.button?.title = service.title
    }

    private func statusClicked() {
        if attachedPanel != nil {
            closeAttached()
        } else {
            openAttached()
        }
    }

    private func openAttached() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }

        let panel = makePanel()
        let size = panel.preferredSize
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))

        var x = buttonFrame.midX - size.width / 2
        if let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame {
            x = min(x, visible.maxX - size.width - 8)
            x = max(x, visible.minX + 8)
        }

        panel.place(topLeft: NSPoint(x: x, y: buttonFrame.minY - 5), size: size)
        attachedPanel = panel
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)
        installMonitors()
    }

    private func makePanel() -> LimonPanel {
        let panel = LimonPanel()
        panel.delegate = self

        let root = MenuPanel(service: service)
            .environmentObject(panel.panelState)
            .environment(\.dismissPanel, { [weak self, weak panel] in
                guard let self, let panel, panel === self.attachedPanel else { return }
                self.closeAttached()
            })
            .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak panel] size in
                panel?.resizeContent(to: size)
            }

        panel.setContent(root)
        return panel
    }

    private func closeAttached() {
        guard let panel = attachedPanel else { return }
        attachedPanel = nil
        removeMonitors()
        statusItem.button?.highlight(false)
        panel.close()
    }

    private func detach(_ panel: LimonPanel) {
        attachedPanel = nil
        removeMonitors()
        statusItem.button?.highlight(false)
        detachedPanels.append(panel)
        panel.markDetached()
        Task { @MainActor [weak self, weak panel] in
            while NSEvent.pressedMouseButtons != 0 {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard let self, let panel,
                  self.detachedPanels.contains(where: { $0 === panel }) else { return }
            panel.completeDetach(alwaysOnTop: self.alwaysOnTop)
            NSApp.setActivationPolicy(.regular)
        }
    }

    func restoreMinimized() {
        for panel in detachedPanels where panel.isMiniaturized {
            panel.deminiaturize(nil)
        }
    }

    private func installMonitors() {
        removeMonitors()

        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] _ in
                let location = NSEvent.mouseLocation
                Task { @MainActor in
                    guard let self, let attached = self.attachedPanel else { return }
                    if attached.frame.contains(location) { return }
                    if let buttonWindow = self.statusItem.button?.window,
                       buttonWindow.frame.contains(location) { return }
                    self.closeAttached()
                }
            }
        ) {
            eventMonitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, let attached = self.attachedPanel else { return event }
                    if let eventWindow = event.window, eventWindow !== attached,
                       eventWindow !== self.statusItem.button?.window {
                        self.closeAttached()
                    }
                    return event
                }
            }
        ) {
            eventMonitors.append(local)
        }

        if let keys = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown],
            handler: { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, self.attachedPanel != nil, event.keyCode == 53 else { return event }
                    self.closeAttached()
                    return nil
                }
            }
        ) {
            eventMonitors.append(keys)
        }
    }

    private func removeMonitors() {
        for monitor in eventMonitors { NSEvent.removeMonitor(monitor) }
        eventMonitors = []
    }

    func windowWillMove(_ notification: Notification) {
        guard let panel = notification.object as? LimonPanel,
              !panel.isRepositioning,
              panel === attachedPanel else { return }
        beginDragTracking(panel)
    }

    func windowDidResize(_ notification: Notification) {
        (notification.object as? LimonPanel)?.repositionTrafficLights()
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? LimonPanel else { return }
        _ = panel.noteUserMovement()
    }

    private func beginDragTracking(_ panel: LimonPanel) {
        guard dragTracker == nil else { return }
        let home = panel.frame.origin
        dragTracker = Task { @MainActor [weak self, weak panel] in
            defer { self?.dragTracker = nil }
            while NSEvent.pressedMouseButtons != 0 {
                guard let self, let panel, panel === self.attachedPanel else { return }
                let offset = hypot(panel.frame.origin.x - home.x,
                                   panel.frame.origin.y - home.y)
                if offset > Self.tearOffDistance {
                    self.detach(panel)
                    return
                }
                try? await Task.sleep(for: .milliseconds(30))
            }
            guard let panel, panel === self?.attachedPanel else { return }
            panel.snapBack(to: home)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? LimonPanel else { return }
        if panel === attachedPanel {
            attachedPanel = nil
            removeMonitors()
            statusItem.button?.highlight(false)
        }
        detachedPanels.removeAll { $0 === panel }
        if detachedPanels.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
