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
    private enum Page: Equatable {
        case main
        case settings
        case image(DockerImage)
        case volume(DockerVolume)
    }

    @ObservedObject var service: ColimaService
    @State private var page = Page.main
    @State private var listContentHeight: CGFloat = 0
    @State private var pageHeight: CGFloat = 0
    @State private var pageSwapping = false
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
        ZStack(alignment: .top) {
            switch page {
            case .main:
                mainPanel
                    .reportPageHeight(setPageHeight)
                    .transition(.opacity)
                    .zIndex(0)
            case .settings:
                SettingsPanel(back: { page = .main })
                    .reportPageHeight(setPageHeight)
                    .slideOverPage()
            case .image(let image):
                ImageInfoPanel(image: image, service: service, back: { page = .main })
                    .reportPageHeight(setPageHeight)
                    .slideOverPage()
            case .volume(let volume):
                VolumeInfoPanel(volume: volume, service: service, back: { page = .main })
                    .reportPageHeight(setPageHeight)
                    .slideOverPage()
            }
        }
        .animation(pageSpring, value: page)
        .frame(width: 320)
        .frame(height: pageHeight == 0 ? nil : pageHeight, alignment: .top)
        .clipped()
        .onChange(of: page) {
            pageSwapping = true
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                pageSwapping = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if (note.object as? NSWindow)?.className.contains("MenuBarExtraWindow") == true {
                page = .main
            }
        }
    }

    private func setPageHeight(_ height: CGFloat) {
        if pageHeight == 0 || !pageSwapping {
            pageHeight = height
        } else if height != pageHeight {
            withAnimation(trailingSpring) { pageHeight = height }
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
                ItemRow(text: image.name, detail: image.size) {
                    page = .image(image)
                }
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
                ItemRow(text: volume.name, detail: volume.driver) {
                    page = .volume(volume)
                }
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
            page = .settings
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
            PanelHeader(title: "Settings", back: back)

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

private struct PanelHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .hoverHighlight(3)
            .help("Back")
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.callout)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private struct ActionRow: View {
    let title: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
    }
}

private struct ImageInfoPanel: View {
    let image: DockerImage
    @ObservedObject var service: ColimaService
    let back: () -> Void

    @State private var details: ImageDetails?

    private var usedBy: [String] {
        service.containers.filter { $0.image == image.name }.map(\.name)
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: image.name, back: back)
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                InfoRow("ID", details.map { String($0.id.replacingOccurrences(of: "sha256:", with: "").prefix(12)) } ?? image.imageID)
                InfoRow("Size", image.size)
                InfoRow("Created", image.createdSince)
                InfoRow("Platform", details.map { "\($0.os)/\($0.architecture)" } ?? "…")
                InfoRow("Used by", usedBy.isEmpty ? "no containers" : usedBy.joined(separator: ", "))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(spacing: 0) {
                ActionRow(title: "Copy Tag") { copyToPasteboard(image.name) }
                ActionRow(title: "Copy ID") { copyToPasteboard(details?.id ?? image.imageID) }
                ActionRow(title: "Delete Image", destructive: true) {
                    service.dockerAction(["rmi", image.name],
                                         label: "removing \(image.name)")
                    back()
                }
            }
            .padding(.vertical, 2)
        }
        .task { details = await service.imageDetails(image.name) }
    }
}

private struct VolumeInfoPanel: View {
    let volume: DockerVolume
    @ObservedObject var service: ColimaService
    let back: () -> Void

    @State private var details: VolumeDetails?
    @State private var users: [String]?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: volume.name, back: back)
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                InfoRow("Driver", volume.driver)
                InfoRow("Created", details.map { formatDockerDate($0.createdAt) } ?? "…")
                InfoRow("Mountpoint", details?.mountpoint ?? "…")
                InfoRow("Scope", details?.scope ?? "…")
                InfoRow("Compose", details.map { $0.labels?["com.docker.compose.project"] ?? "—" } ?? "…")
                InfoRow("Used by", users.map { $0.isEmpty ? "no containers" : $0.joined(separator: ", ") } ?? "…")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(spacing: 0) {
                ActionRow(title: "Copy Name") { copyToPasteboard(volume.name) }
                ActionRow(title: "Copy Mountpoint") {
                    if let mountpoint = details?.mountpoint { copyToPasteboard(mountpoint) }
                }
                .disabled(details == nil)
                ActionRow(title: "Delete Volume", destructive: true) {
                    service.dockerAction(["volume", "rm", volume.name],
                                         label: "removing \(volume.name)")
                    back()
                }
            }
            .padding(.vertical, 2)
        }
        .task {
            async let fetched = service.volumeDetails(volume.name)
            async let names = service.volumeUsers(volume.name)
            details = await fetched
            users = await names
        }
    }
}

private func formatDockerDate(_ raw: String) -> String {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = iso.date(from: raw)
    if date == nil {
        iso.formatOptions = [.withInternetDateTime]
        date = iso.date(from: raw)
    }
    guard let date else { return raw }
    return date.formatted(date: .abbreviated, time: .shortened)
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
private let pageSpring = Animation.spring(duration: 0.3, bounce: 0.05)

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

private struct ItemRow: View {
    let text: String
    let detail: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
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
        .help("Show info")
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
    var closesPanel = true
    let action: () -> Void

    var body: some View {
        Button {
            action()
            if closesPanel { closePanel() }
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

    func reportPageHeight(_ update: @escaping (CGFloat) -> Void) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.height } action: { update($0) }
    }

    func slideOverPage() -> some View {
        self.background(.regularMaterial)
            .compositingGroup()
            .shadow(color: .black.opacity(0.25), radius: 10, x: -5, y: 0)
            .transition(.move(edge: .trailing))
            .zIndex(1)
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
