import SwiftUI
import AppKit
import ServiceManagement

@main
struct LimonApp: App {
    @StateObject private var service = ColimaService()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(service: service)
        } label: {
            Text(service.title)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuPanel: View {
    @ObservedObject var service: ColimaService
    @State private var showingSettings = false
    @State private var listContentHeight: CGFloat = 0
    @State private var imagesExpanded = false
    @State private var volumesExpanded = false

    private var running: [DockerContainer] {
        service.containers
            .filter(\.isRunning)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var recentlyExited: [DockerContainer] {
        Array(service.containers.filter(\.isExited).prefix(3))
    }

    var body: some View {
        Group {
            if showingSettings {
                SettingsPanel(back: { showingSettings = false })
            } else {
                mainPanel
            }
        }
        .frame(width: 320)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if (note.object as? NSWindow)?.className.contains("MenuBarExtraWindow") == true {
                showingSettings = false
            }
        }
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            settingsRow
        }
    }


    private var header: some View {
        HStack(spacing: 8) {
            Text("🍋")
            Text("Limón")
                .font(.headline)
            Spacer()
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var summary: String {
        if service.busy != nil { return "Working…" }
        if service.colima == nil { return "colima not found" }
        guard service.isRunning else { return "Colima stopped" }
        let count = running.count
        return count == 1 ? "1 running" : "\(count) running"
    }


    @ViewBuilder
    private var content: some View {
        if let busy = service.busy {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("\(busy)…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else if service.colima == nil {
            VStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("colima not found")
                    .font(.callout)
                Text("Searched Homebrew, mise/asdf shims, and your login shell")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
        } else if !service.isRunning {
            VStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Colima stopped")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Start Colima") {
                    service.colimaAction(["start"], label: "starting colima")
                    closePanel()
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else {
            containerList
        }
    }

    private static let listCap: CGFloat = 400

    private var containerList: some View {
        Group {
            if listContentHeight > Self.listCap {
                ScrollView {
                    listContent
                }
                .frame(height: Self.listCap)
            } else {
                listContent
                    .frame(height: listContentHeight == 0 ? nil : listContentHeight,
                           alignment: .top)
                    .clipped()
            }
        }
    }

    private var listContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            hostRow
            Divider()
                .padding(.vertical, 2)

            if running.isEmpty {
                Text("No running containers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(running) { container in
                    RunningRow(container: container, service: service)
                }
            }

            if !recentlyExited.isEmpty {
                Text("Recently exited")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(recentlyExited) { container in
                    ExitedRow(container: container, service: service)
                }
            }

            Divider()
                .padding(.vertical, 2)
                .opacity(imagesExpanded ? 0 : 1)
            imagesSection
            volumesSection
        }
        .padding(12)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if listContentHeight == 0 {
                listContentHeight = height
            } else if height != listContentHeight {
                withAnimation(trailingSpring) { listContentHeight = height }
            }
        }
    }


    private func accordionCard<Content: View>(
        expanded: Bool, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .padding(.vertical, expanded ? 8 : 0)
            .background(
                Rectangle()
                    .fill(.quinary)
                    .opacity(expanded ? 1 : 0)
                    .padding(.horizontal, -12)
            )
            .overlay(alignment: .top) {
                Divider().padding(.horizontal, -12).opacity(expanded ? 1 : 0)
            }
            .overlay(alignment: .bottom) {
                Divider().padding(.horizontal, -12).opacity(expanded ? 1 : 0)
            }
    }

    private var imagesSection: some View {
        accordionCard(expanded: imagesExpanded) {
            AccordionHeader(title: "Images", count: service.images.count,
                            expanded: $imagesExpanded)
            imagesRows
        }
    }

    @ViewBuilder
    private var imagesRows: some View {
        if imagesExpanded {
            let tagged = service.images.filter { !$0.isDangling }
            let dangling = service.images.count - tagged.count

            if service.images.isEmpty {
                Text("No images")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 13)
            }
            ForEach(tagged) { image in
                CopyRow(text: image.name, detail: image.size)
            }
            if dangling > 0 {
                PruneRow(label: dangling == 1 ? "1 dangling image" : "\(dangling) dangling images") {
                    service.dockerAction(["image", "prune", "-f"],
                                         label: "pruning images")
                }
            }
        }
    }

    private var volumesSection: some View {
        accordionCard(expanded: volumesExpanded) {
            AccordionHeader(title: "Volumes", count: service.volumes.count,
                            expanded: $volumesExpanded)
            volumesRows
        }
    }

    @ViewBuilder
    private var volumesRows: some View {
        if volumesExpanded {
            if service.volumes.isEmpty {
                Text("No volumes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 13)
            }
            ForEach(service.volumes) { volume in
                CopyRow(text: volume.name, detail: volume.driver)
            }
            let unused = service.unusedVolumes.count
            if unused > 0 {
                PruneRow(label: unused == 1 ? "1 unused volume" : "\(unused) unused volumes") {
                    service.dockerAction(["volume", "prune", "-f"],
                                         label: "pruning volumes")
                }
            }
        }
    }


    private var hostRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
            Text("colima")
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 4)

            IconButton(systemImage: "terminal", help: "SSH into VM") {
                service.openInTerminal([service.colima ?? "colima", "ssh"])
            }
            IconButton(systemImage: "arrow.clockwise", help: "Restart Colima") {
                service.colimaAction(["restart"], label: "restarting colima")
            }
            IconButton(systemImage: "stop.fill", help: "Stop Colima") {
                service.colimaAction(["stop"], label: "stopping colima")
            }
        }
    }

    private var settingsRow: some View {
        Button {
            showingSettings = true
        } label: {
            HStack {
                Text("Settings")
                    .font(.callout)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }
}


private struct SettingsPanel: View {
    let back: () -> Void

    @AppStorage("refreshSeconds") private var refreshSeconds = 5
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .hoverHighlight(3)
                .help("Back")
                Text("Settings")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                sectionLabel("Refresh Every")
                ForEach([2, 5, 10], id: \.self) { seconds in
                    CheckRow(label: "\(seconds) seconds",
                             selected: refreshSeconds == seconds) {
                        refreshSeconds = seconds
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                sectionLabel("General")
                CheckRow(label: "Launch at Login", selected: launchAtLogin) {
                    toggleLoginItem()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Text("Quit Limón")
                        .font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .keyboardShortcut("q")
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 2)
    }

    private func toggleLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchAtLogin.toggle()
        } catch {
            NSSound.beep()
        }
    }
}

private struct CheckRow: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .opacity(selected ? 1 : 0)
                    .frame(width: 14)
                Text(label)
                    .font(.callout)
                Spacer()
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(3)
    }
}


private struct RunningRow: View {
    let container: DockerContainer
    @ObservedObject var service: ColimaService

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
            Text(container.name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(container.image)

            Spacer(minLength: 4)

            if let port = container.publicPort {
                Button {
                    copyToPasteboard("localhost:\(port)")
                } label: {
                    Text(verbatim: ":\(port)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .hoverHighlight(3)
                .help("Copy localhost:\(port)")

                IconButton(systemImage: "safari", help: "Open in browser") {
                    if let url = URL(string: "http://localhost:\(port)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            IconButton(systemImage: "terminal", help: "Logs") { openLogs() }
            IconButton(systemImage: "stop.fill", help: "Stop") {
                service.dockerAction(["stop", container.containerID],
                                     label: "stopping \(container.name)")
            }
            IconButton(systemImage: "arrow.clockwise", help: "Restart") {
                service.dockerAction(["restart", container.containerID],
                                     label: "restarting \(container.name)")
            }
        }
        .contextMenu {
            Text(container.image)
            Text(container.status)
            Divider()
            Button("Logs") {
                openLogs()
                closePanel()
            }
            Button("Shell") {
                service.openInTerminal([
                    service.docker ?? "docker",
                    "exec", "-it", container.shortID, "/bin/sh",
                ])
                closePanel()
            }
            Divider()
            Button("Restart") {
                service.dockerAction(["restart", container.containerID],
                                     label: "restarting \(container.name)")
                closePanel()
            }
            Button("Stop") {
                service.dockerAction(["stop", container.containerID],
                                     label: "stopping \(container.name)")
                closePanel()
            }
            Divider()
            Button("Copy Container ID") { copyToPasteboard(container.containerID) }
        }
    }

    private func openLogs() {
        service.openInTerminal([
            service.docker ?? "docker",
            "logs", "-f", "--tail", "200", container.shortID,
        ])
    }
}

private struct ExitedRow: View {
    let container: DockerContainer
    @ObservedObject var service: ColimaService

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.orange)
                .frame(width: 7, height: 7)
            Text(container.name)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(container.status)

            Spacer(minLength: 4)

            IconButton(systemImage: "play.fill", help: "Start") {
                service.dockerAction(["start", container.containerID],
                                     label: "starting \(container.name)")
            }
        }
    }
}


private let accordionSpring = Animation.spring(duration: 0.3, bounce: 0.1)
private let trailingSpring = Animation.spring(duration: 0.45, bounce: 0.15)

private struct AccordionHeader: View {
    let title: String
    let count: Int
    @Binding var expanded: Bool

    var body: some View {
        Button {
            withAnimation(accordionSpring) { expanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(3)
    }
}

private struct CopyRow: View {
    let text: String
    let detail: String

    var body: some View {
        Button {
            copyToPasteboard(text)
        } label: {
            HStack(spacing: 6) {
                Text(text)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(3)
        .padding(.leading, 13)
        .help("Copy \(text)")
    }
}

private struct PruneRow: View {
    let label: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("Prune", action: action)
                .controlSize(.mini)
        }
        .padding(.leading, 13)
    }
}


private struct IconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button {
            action()
            closePanel()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .hoverHighlight(3)
        .help(help)
    }
}

private struct HoverHighlight: ViewModifier {
    let inset: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(hovering ? 1 : 0))
                    .padding(-inset)
            )
            .onHover { hovering = $0 }
    }
}

private extension View {
    func hoverHighlight(_ inset: CGFloat = 0) -> some View {
        modifier(HoverHighlight(inset: inset))
    }
}

private func copyToPasteboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}

@MainActor
private func closePanel() {
    let panel = NSApp.windows.first { $0.className.contains("MenuBarExtraWindow") }
        ?? NSApp.keyWindow
    panel?.close()
}
