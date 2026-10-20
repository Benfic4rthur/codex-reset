import AppKit
import Combine
import SwiftUI

private enum CompanionIdentity {
    static let chatGPTBundleID = "com.openai.codex"
}

@main
enum CodexResetApp {
    @MainActor private static let delegate = AppDelegate()

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = DashboardStore()
    private var window: NotchWindow?
    private var hostTerminationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: CompanionIdentity.chatGPTBundleID
        ).contains(where: { !$0.isTerminated }) else {
            NSApp.terminate(nil)
            return
        }

        window = NotchWindow(store: store)
        store.start()
        hostTerminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  application.bundleIdentifier == CompanionIdentity.chatGPTBundleID else { return }
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hostTerminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(hostTerminationObserver)
        }
        store.stop()
        window?.stop()
    }
}

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var usage: UsageSnapshot?
    @Published private(set) var usageError: String?
    @Published private(set) var activeThreads: [ActiveThread] = []
    @Published private(set) var threadsError: String?
    @Published private(set) var forecast: ResetForecast?
    @Published private(set) var forecastError: String?
    @Published var listExpanded = false
    @Published var showHoverDetails = false

    var rootThreads: [ActiveThread] {
        activeThreads.filter { !$0.isSubagent }.sorted(by: Self.heavier)
    }

    var heaviestThread: ActiveThread? { rootThreads.first }

    private var threadsTimer: Timer?
    private var usageTimer: Timer?
    private var forecastTimer: Timer?
    private var hoverWork: DispatchWorkItem?
    private var threadsInFlight = false
    private var usageInFlight = false
    private var forecastInFlight = false

    func start() {
        refreshThreads()
        refreshUsage()
        refreshForecast()
        threadsTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshThreads() }
        }
        usageTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshUsage() }
        }
        forecastTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshForecast() }
        }
    }

    func stop() {
        threadsTimer?.invalidate()
        usageTimer?.invalidate()
        forecastTimer?.invalidate()
        hoverWork?.cancel()
    }

    func setHover(_ inside: Bool) {
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.showHoverDetails = inside
            if !inside { self.listExpanded = false }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.18 : 0.30), execute: work)
    }

    func toggleThreads() {
        guard rootThreads.count > 1 else { return }
        listExpanded.toggle()
        if listExpanded { showHoverDetails = true }
    }

    func refreshThreads() {
        guard !threadsInFlight else { return }
        threadsInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try ActiveThreadReader.readThrowing() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.threadsInFlight = false
                switch result {
                case .success(let threads):
                    if self.activeThreads != threads { self.activeThreads = threads }
                    if self.rootThreads.count <= 1 { self.listExpanded = false }
                    self.threadsError = nil
                case .failure(let error):
                    self.threadsError = error.localizedDescription
                }
            }
        }
    }

    func refreshUsage() {
        guard !usageInFlight else { return }
        usageInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try CodexClient.fetchUsage() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.usageInFlight = false
                switch result {
                case .success(let snapshot):
                    self.usage = snapshot
                    self.usageError = nil
                case .failure(let error):
                    self.usageError = error.localizedDescription
                }
            }
        }
    }

    func refreshForecast() {
        guard !forecastInFlight else { return }
        forecastInFlight = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.forecastInFlight = false }
            do {
                self.forecast = try await ResetForecastService.fetch()
                self.forecastError = nil
            } catch {
                self.forecastError = error.localizedDescription
            }
        }
    }

    private static func heavier(_ lhs: ActiveThread, _ rhs: ActiveThread) -> Bool {
        let leftEffort = effortRank(lhs.effort)
        let rightEffort = effortRank(rhs.effort)
        if leftEffort != rightEffort { return leftEffort > rightEffort }
        let leftModel = modelRank(lhs.model)
        let rightModel = modelRank(rhs.model)
        if leftModel.family != rightModel.family { return leftModel.family > rightModel.family }
        if leftModel.version != rightModel.version { return leftModel.version > rightModel.version }
        return (lhs.startedAt ?? .distantPast) > (rhs.startedAt ?? .distantPast)
    }

    private static func effortRank(_ effort: String) -> Int {
        switch effort.lowercased() {
        case "ultra": return 6
        case "max": return 5
        case "xhigh": return 4
        case "high": return 3
        case "medium": return 2
        case "low": return 1
        default: return 0
        }
    }

    private static func modelRank(_ model: String) -> (family: Int, version: Int) {
        let name = model.lowercased()
        let family: Int
        if name.contains("astra") { family = 4 }
        else if name.contains("sol") { family = 3 }
        else if name.contains("terra") { family = 2 }
        else if name.contains("luna") { family = 1 }
        else { family = 0 }

        guard let marker = name.range(of: "gpt-") else { return (family, 0) }
        let number = name[marker.upperBound...].prefix { $0.isNumber || $0 == "." }
        let pieces = number.split(separator: ".")
        let major = pieces.first.flatMap { Int($0) } ?? 0
        let minor = pieces.dropFirst().first.flatMap { Int($0) } ?? 0
        return (family, major * 100 + minor)
    }
}

private struct NotchGeometry {
    let screen: NSScreen
    let centerX: CGFloat
    let gapWidth: CGFloat
    let compactHeight: CGFloat
    let leftWingWidth: CGFloat = 48
    let rightWingWidth: CGFloat = 112
    let detailHeight: CGFloat = 70
    let listDetailHeight: CGFloat = 102

    init(screen: NSScreen) {
        self.screen = screen
        let left = screen.auxiliaryTopLeftArea?.maxX
        let right = screen.auxiliaryTopRightArea?.minX
        let physicalGap = (left != nil && right != nil) ? max(0, right! - left!) : 0
        centerX = physicalGap > 100 ? (left! + right!) / 2 : screen.frame.midX
        gapWidth = physicalGap > 100 ? physicalGap : 160
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let reservedTop = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : menuBarHeight
        compactHeight = max(24, reservedTop - 2)
    }

    var compactWidth: CGFloat { leftWingWidth + gapWidth + rightWingWidth }
    var expandedWidth: CGFloat { compactWidth }
    var envelopeWidth: CGFloat { expandedWidth + 8 }
    var envelopeHeight: CGFloat { compactHeight + listDetailHeight + 8 }
    var surfaceCenterX: CGFloat { centerX + (rightWingWidth - leftWingWidth) / 2 }
    var frame: CGRect {
        CGRect(x: surfaceCenterX - envelopeWidth / 2,
               y: screen.frame.maxY - envelopeHeight,
               width: envelopeWidth, height: envelopeHeight)
    }

    func topContains(_ point: CGPoint) -> Bool {
        let x = (envelopeWidth - compactWidth) / 2
        return point.x >= x && point.x <= x + compactWidth
            && point.y >= envelopeHeight - compactHeight && point.y <= envelopeHeight
    }

    func detailContains(_ point: CGPoint, height: CGFloat) -> Bool {
        let x = (envelopeWidth - expandedWidth) / 2
        return point.x >= x && point.x <= x + expandedWidth
            && point.y >= envelopeHeight - compactHeight - height
            && point.y < envelopeHeight - compactHeight
    }

    func disclosureContains(_ point: CGPoint) -> Bool {
        let rightEdge = (envelopeWidth + compactWidth) / 2
        return point.x >= rightEdge - 26 && point.x <= rightEdge
            && point.y >= envelopeHeight - compactHeight && point.y <= envelopeHeight
    }
}

@MainActor
private final class NotchWindow: NSObject {
    private let store: DashboardStore
    private let panel: NSPanel
    private var geometry: NotchGeometry
    private var hostingView: NSHostingView<NotchRootView>?
    private var pointerTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var pointerInside = false

    init(store: DashboardStore) {
        self.store = store
        let screen = NSScreen.main ?? NSScreen.screens[0]
        geometry = NotchGeometry(screen: screen)
        panel = NSPanel(contentRect: geometry.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        super.init()
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        let host = NSHostingView(rootView: NotchRootView(store: store, geometry: geometry))
        host.frame = CGRect(origin: .zero, size: geometry.frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        hostingView = host
        panel.orderFrontRegardless()

        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshScreen() } }
    }

    private func refreshScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        geometry = NotchGeometry(screen: screen)
        panel.setFrame(geometry.frame, display: true)
        hostingView?.rootView = NotchRootView(store: store, geometry: geometry)
        updatePointer()
    }

    private func updatePointer() {
        let point = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let detailHeight = store.listExpanded ? geometry.listDetailHeight : geometry.detailHeight
        let hovering = geometry.topContains(point)
            || ((store.showHoverDetails || store.listExpanded)
                && geometry.detailContains(point, height: detailHeight))
        if hovering != pointerInside {
            pointerInside = hovering
            store.setHover(hovering)
        }
        let clickable = (store.rootThreads.count > 1 && geometry.disclosureContains(point))
            || ((store.showHoverDetails || store.listExpanded)
                && geometry.detailContains(point, height: detailHeight))
        panel.ignoresMouseEvents = !clickable
    }

    func stop() {
        pointerTimer?.invalidate()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        panel.close()
    }
}

private enum Visual {
    static let primary = Color.white.opacity(0.97)
    static let secondary = Color.white.opacity(0.76)
    static let muted = Color.white.opacity(0.62)
    static let accent = Color(red: 0.40, green: 0.83, blue: 0.76)
}

private struct NotchSurface: Shape {
    let width: CGFloat
    let compactHeight: CGFloat
    var visibleDepth: CGFloat

    var animatableData: CGFloat {
        get { visibleDepth }
        set { visibleDepth = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let depth = max(0, visibleDepth)
        let center = rect.midX
        let left = center - width / 2
        let right = center + width / 2
        let bottom = compactHeight + depth
        let corner: CGFloat = 17

        var path = Path()
        path.move(to: CGPoint(x: left, y: 0))
        path.addLine(to: CGPoint(x: right, y: 0))
        path.addLine(to: CGPoint(x: right, y: bottom - corner))
        path.addQuadCurve(
            to: CGPoint(x: right - corner, y: bottom),
            control: CGPoint(x: right, y: bottom)
        )
        path.addLine(to: CGPoint(x: left + corner, y: bottom))
        path.addQuadCurve(
            to: CGPoint(x: left, y: bottom - corner),
            control: CGPoint(x: left, y: bottom)
        )
        path.addLine(to: CGPoint(x: left, y: 0))
        path.closeSubpath()
        return path
    }
}

private struct NotchRootView: View {
    @ObservedObject var store: DashboardStore
    let geometry: NotchGeometry

    var body: some View {
        let expanded = store.showHoverDetails || store.listExpanded
        let detailHeight = store.listExpanded ? geometry.listDetailHeight : geometry.detailHeight
        let visibleDepth = expanded ? detailHeight : 0
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                QuotaCompactView(store: store)
                    .frame(width: geometry.leftWingWidth, height: geometry.compactHeight)
                Color.clear.frame(width: geometry.gapWidth, height: geometry.compactHeight)
                ThreadCompactView(store: store)
                    .frame(width: geometry.rightWingWidth, height: geometry.compactHeight)
            }
            .frame(width: geometry.compactWidth, height: geometry.compactHeight)

            CenteredDetailView(store: store, height: detailHeight, contentWidth: geometry.compactWidth - 32)
                .frame(width: geometry.expandedWidth, height: detailHeight)
                .frame(height: visibleDepth, alignment: .top)
                .clipped()

            Spacer(minLength: 0)
        }
        .frame(width: geometry.envelopeWidth, height: geometry.envelopeHeight, alignment: .top)
        .foregroundStyle(Visual.primary)
        .background(alignment: .top) {
            NotchSurface(
                width: geometry.compactWidth,
                compactHeight: geometry.compactHeight,
                visibleDepth: visibleDepth
            )
            .fill(.black)
            .frame(width: geometry.envelopeWidth, height: geometry.envelopeHeight)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: visibleDepth)
    }
}

private struct QuotaCompactView: View {
    @ObservedObject var store: DashboardStore

    var body: some View {
        ZStack {
            Circle()
                .stroke(Visual.muted.opacity(0.34), lineWidth: 2.7)
            Circle()
                .trim(from: 0, to: remainingFraction)
                .stroke(Visual.accent, style: StrokeStyle(lineWidth: 2.7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(percentage)
                .font(.system(size: percentage == "100%" ? 8 : 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(width: 30, height: 30)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 12)
        .animation(.easeInOut(duration: 0.35), value: remainingFraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Franquia semanal do Codex: " + percentage + " restante")
    }

    private var remainingFraction: CGFloat {
        guard let remaining = store.usage?.displayedWindow?.remainingPercent else { return 0 }
        return CGFloat(min(1, max(0, remaining / 100)))
    }

    private var percentage: String {
        guard let quota = store.usage?.displayedWindow else { return "—%" }
        return "\(Int(quota.remainingPercent.rounded()))%"
    }
}

private struct ThreadCompactView: View {
    @ObservedObject var store: DashboardStore

    var body: some View {
        if let thread = store.heaviestThread {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2) {
                Text(thread.projectName)
                    .font(.system(size: 9.2, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(Visual.primary)
                Spacer(minLength: 0)
                if store.rootThreads.count > 1 {
                    Button { store.toggleThreads() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .rotationEffect(.degrees(store.listExpanded ? 180 : 0))
                            .frame(width: 16, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Visual.primary)
                    .accessibilityLabel(store.listExpanded ? "Ocultar outras conversas" : "Mostrar outras conversas")
                    .help(store.listExpanded ? "Ocultar outras conversas" : "Mostrar outras conversas")
                }
            }
            HStack(spacing: 3) {
                Text(Format.model(thread.model))
                    .foregroundStyle(Visual.secondary)
                Text("·").foregroundStyle(Visual.muted)
                Text(Format.effort(thread.effort))
                    .foregroundStyle(Visual.accent)
            }
            .font(.system(size: 8, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 6)
        .padding(.trailing, 4)
        }
    }
}

private struct CenteredDetailView: View {
    @ObservedObject var store: DashboardStore
    let height: CGFloat
    let contentWidth: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 2) {
                        Text("RESET EXTRA").detailHeading()
                        Text(extraHeadline(at: context.date))
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                        Text(extraCaption)
                            .font(.system(size: 9))
                            .foregroundStyle(Visual.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 1, height: 38)
                        .padding(.horizontal, 13)
                        .padding(.top, 2)

                    VStack(spacing: 2) {
                        Text("RESET SEMANAL").detailHeading()
                        Text(weeklyHeadline(at: context.date))
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                }
                .frame(width: contentWidth)
                .padding(.top, 12)

                if store.listExpanded && store.rootThreads.count > 1 {
                    VStack(spacing: 3) {
                        Text("OUTRAS CONVERSAS · \(store.rootThreads.count - 1)")
                            .detailHeading()
                        ScrollView(.vertical, showsIndicators: store.rootThreads.count > 3) {
                            VStack(spacing: 3) {
                                ForEach(store.rootThreads.dropFirst()) { thread in
                                    HStack(spacing: 5) {
                                        Text(thread.projectName)
                                            .fontWeight(.medium)
                                            .lineLimit(1)
                                        Spacer(minLength: 8)
                                        Text(Format.model(thread.model))
                                        Text("·").foregroundStyle(Visual.muted)
                                        Text(Format.effort(thread.effort))
                                            .foregroundStyle(Visual.accent)
                                    }
                                    .font(.system(size: 9))
                                    .foregroundStyle(Visual.secondary)
                                    .lineLimit(1)
                                }
                            }
                        }
                        .frame(height: 28)
                    }
                    .frame(width: contentWidth)
                    .padding(.top, 11)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            .multilineTextAlignment(.center)
            .overlay(alignment: .topTrailing) {
                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Visual.muted)
                .accessibilityLabel("Fechar Codex Reset")
                .padding(.trailing, 13)
                .padding(.top, 6)
            }
        }
    }

    private func extraHeadline(at now: Date) -> String {
        guard let forecast = store.forecast else {
            return store.forecastError == nil ? "Buscando previsão…" : "Previsão indisponível"
        }
        if let announcement = forecast.scheduledReset {
            if let date = announcement.scheduledFor, date > now {
                return "Anunciado para \(Format.date(date))"
            }
            return "Reset extra anunciado"
        }
        if let window = forecast.likelyWindow { return "Possível \(window)" }
        return "Sem previsão confiável"
    }

    private var extraCaption: String {
        guard let forecast = store.forecast else {
            return store.forecastError == nil ? "Histórico em atualização" : "Fonte indisponível"
        }
        if forecast.scheduledReset != nil { return "Anúncio verificado na fonte" }
        guard let chance = forecast.probabilityNext7Days else {
            return "Histórico insuficiente para estimar"
        }
        return "Chance histórica em 7 dias: \(Int((chance * 100).rounded()))%"
    }

    private func weeklyHeadline(at now: Date) -> String {
        guard let reset = store.usage?.weeklyWindow?.resetsAt else {
            return "Horário ainda indisponível"
        }
        let seconds = reset.timeIntervalSince(now)
        guard seconds > 0 else { return "Aguardando atualização" }
        let minutes = Int(seconds / 60)
        let days = minutes / 1_440
        let hours = (minutes / 60) % 24
        if days > 0 { return "Em \(days)d \(hours)h" }
        if hours > 0 { return "Em \(hours)h \(minutes % 60)min" }
        return "Em \(max(1, minutes)) min"
    }

}

private extension View {
    func detailHeading() -> some View {
        font(.system(size: 8, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(Visual.muted)
    }
}

private enum Format {
    static func model(_ value: String) -> String {
        let pieces = value.split(separator: "-").map(String.init)
        guard pieces.count > 1, pieces[0].lowercased() == "gpt" else { return value }
        return (["GPT-\(pieces[1])"] + pieces.dropFirst(2).map { $0.capitalized }).joined(separator: " ")
    }

    static func effort(_ value: String) -> String {
        switch value.lowercased() {
        case "xhigh": return "X-high"
        case "ultra": return "Ultra"
        case "max": return "Max"
        case "high": return "High"
        case "medium": return "Medium"
        case "low": return "Low"
        default: return value
        }
    }

    static func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter.string(from: value)
    }
}
