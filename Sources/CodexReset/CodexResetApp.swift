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
    private lazy var settings = SettingsWindowController(store: store)
    private var hostTerminationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do {
            try CompanionRegistration.installIfNeeded()
        } catch {
            NSLog("Codex Reset: início automático indisponível: %@", error.localizedDescription)
        }
        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: CompanionIdentity.chatGPTBundleID
        ).contains(where: { !$0.isTerminated }) else {
            NSApp.terminate(nil)
            return
        }

        window = NotchWindow(store: store)
        store.onOpenSettings = { [weak self] in self?.settings.show() }
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }
}

@MainActor
final class DashboardStore: ObservableObject {
    @Published var preferences: DashboardPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: "displayPreferences") }
            if !canExpandConversations { listExpanded = false }
            if !preferences.highlightNewReset { showNewResetInPanel = false }
        }
    }
    @Published private(set) var lastResetNotice: LastResetNotice?
    @Published private(set) var showNewResetInPanel = false
    var onOpenSettings: (() -> Void)?
    @Published private(set) var usage: UsageSnapshot?
    @Published private(set) var usageError: String?
    @Published private(set) var activeThreads: [ActiveThread] = []
    @Published private(set) var threadsError: String?
    @Published private(set) var forecast: ResetForecast?
    @Published private(set) var forecastError: String?
    @Published private(set) var isRefreshingForecast = false
    @Published var showsAnnouncement = false
    @Published var translatedPosts: [String: String] = [:]
    @Published var listExpanded = false
    @Published var showHoverDetails = false

    var rootThreads: [ActiveThread] {
        activeThreads.filter { !$0.isSubagent }.sorted(by: Self.heavier)
    }

    var heaviestThread: ActiveThread? { rootThreads.first }
    var hasTopContent: Bool { !topContent.isEmpty }
    var canExpandConversations: Bool { hasTopContent && preferences.showConversations && rootThreads.count > 1 }
    var topContent: [[DashboardCell]] {
        preferences.topRows.map { row in row.compactMap { field in
            text(for: field).map { DashboardCell(field: field, text: $0) }
        }}.filter { !$0.isEmpty }
    }

    func text(for field: DashboardField, at now: Date = Date()) -> String? {
        switch field {
        case .conversation: return heaviestThread?.title
        case .project: return heaviestThread?.projectName
        case .model: return heaviestThread.map { preferences.compactModelName ? Format.shortModel($0.model) : Format.model($0.model) }
        case .effort: return heaviestThread.map { Format.effort($0.effort) }
        case .tokenRate: return Format.tokenRate(heaviestThread?.tokenRate)
        case .outputTokenRate: return Format.tokenRate(heaviestThread?.outputTokenRate)
        case .activeCount: return "\(rootThreads.count) ativa\(rootThreads.count == 1 ? "" : "s")"
        case .quota: return usage?.displayedWindow.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—%"
        case .extraReset: return forecast?.presentation(at: now).headline.replacingOccurrences(of: "\n", with: " ")
            ?? (isRefreshingForecast || forecastError == nil ? "Buscando previsão…" : "Previsão indisponível")
        case .weeklyReset: return usage?.weeklyWindow?.resetsAt.flatMap { ResetCountdown.remaining(until: $0, at: now) }.map { "Em " + $0 } ?? "Aguardando atualização"
        case .lastReset: return lastResetNotice.map { $0.elapsed(at: now) } ?? "Ainda não observado"
        case .tiboAnnouncement: return "Tibo"
        }
    }
    var hasUnseenReset: Bool { preferences.highlightNewReset && lastResetNotice?.isUnseen == true }

    func tokenRateDescription(for field: DashboardField) -> String {
        let description = field == .outputTokenRate
            ? "Somente tokens de saída, incluindo raciocínio. Média entre atualizações, não velocidade instantânea."
            : "Entrada + saída, incluindo contexto em cache. Não equivale à franquia debitada nem à velocidade de geração."
        guard let thread = heaviestThread, let date = thread.tokenRateSampledAt else {
            return description + " O Codex ainda não informou duas amostras recentes."
        }
        return description + " Amostra de " + date.formatted(date: .omitted, time: .standard)
            + (field == .tokenRate ? ". Cache incluído: " + Format.tokenRate(thread.cachedInputTokenRate) : "")
    }

    private var threadsTimer: Timer?
    private var usageTimer: Timer?
    private var forecastTimer: Timer?
    private var hoverWork: DispatchWorkItem?
    private var threadsInFlight = false
    private var usageInFlight = false
    private var sourceForecast: ResetForecast?
    private var observedQuotaReset: Date?
    private let forecastLoader: @Sendable () async throws -> ResetForecast
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, forecastLoader: @escaping @Sendable () async throws -> ResetForecast = {
        try await ResetForecastService.fetch()
    }) {
        self.defaults = defaults
        preferences = defaults.data(forKey: "displayPreferences")
            .flatMap { try? JSONDecoder().decode(DashboardPreferences.self, from: $0) } ?? DashboardPreferences()
        lastResetNotice = defaults.data(forKey: "lastResetNotice")
            .flatMap { try? JSONDecoder().decode(LastResetNotice.self, from: $0) }
        self.forecastLoader = forecastLoader
    }

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
        forecastTimer = Timer.scheduledTimer(withTimeInterval: ResetForecastService.refreshInterval, repeats: true) { [weak self] _ in
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
            if inside && !self.showHoverDetails { self.panelOpened() }
            self.showHoverDetails = inside
            if !inside { self.listExpanded = false }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.18 : 0.30), execute: work)
    }

    func toggleThreads() {
        guard canExpandConversations else { return }
        listExpanded.toggle()
        if listExpanded {
            if !showHoverDetails { panelOpened() }
            showHoverDetails = true
        }
    }

    func panelOpened() {
        showNewResetInPanel = preferences.highlightNewReset && lastResetNotice?.isNew == true
        if showNewResetInPanel {
            lastResetNotice?.presented()
            saveResetNotice()
        }
    }

    private func saveResetNotice() {
        if let data = try? JSONEncoder().encode(lastResetNotice) { defaults.set(data, forKey: "lastResetNotice") }
    }

    private func observeLastReset(_ date: Date?, at now: Date) {
        guard let date, date <= now, date > (lastResetNotice?.date ?? .distantPast) else { return }
        lastResetNotice = LastResetNotice(date: date, presentations: now.timeIntervalSince(date) > 86_400 ? 3 : 0)
        if showHoverDetails { panelOpened() } else { saveResetNotice() }
    }

    func refreshThreads() {
        guard !threadsInFlight else { return }
        threadsInFlight = true
        let fields = Array(preferences.topRows.joined()) + Array(preferences.detailRows.joined())
        let includeTokens = fields.contains(.tokenRate) || fields.contains(.outputTokenRate)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try ActiveThreadReader.readThrowing(includeTokenRate: includeTokens) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.threadsInFlight = false
                switch result {
                case .success(let threads):
                    if self.activeThreads != threads { self.activeThreads = threads }
                    if !self.canExpandConversations { self.listExpanded = false }
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
                    self.receiveUsage(snapshot)
                case .failure(let error):
                    self.usageError = error.localizedDescription
                }
            }
        }
    }

    func receiveUsage(_ snapshot: UsageSnapshot) {
        let observed = QuotaResetObservation.detectedAt(previous: usage, current: snapshot, forecast: sourceForecast)
        if let quota = snapshot.weeklyWindow, let end = quota.resetsAt, let duration = quota.durationMinutes {
            observeLastReset(end.addingTimeInterval(-Double(duration) * 60), at: snapshot.fetchedAt)
        }
        observeLastReset(observed, at: snapshot.fetchedAt)
        usage = snapshot
        usageError = nil
        if recordQuotaReset(observed) {
            forecast = sourceForecast?.reconcilingQuotaReset(at: observedQuotaReset)
            refreshForecast()
        }
    }

    private func recordQuotaReset(_ date: Date?) -> Bool {
        let latest = max(observedQuotaReset ?? .distantPast, sourceForecast?.latest ?? .distantPast)
        guard let date, date > latest else { return false }
        observedQuotaReset = date
        return true
    }

    func refreshForecast(using fetch: (@Sendable () async throws -> ResetForecast)? = nil) {
        guard !isRefreshingForecast else { return }
        isRefreshingForecast = true
        let load = fetch ?? forecastLoader
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRefreshingForecast = false }
            do {
                let source = try await load()
                self.sourceForecast = source
                if let usage = self.usage {
                    _ = self.recordQuotaReset(QuotaResetObservation.detectedAt(
                        previous: nil, current: usage, forecast: source))
                }
                self.forecast = source.reconcilingQuotaReset(at: self.observedQuotaReset)
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

@MainActor
private final class NotchWindow: NSObject {
    private let store: DashboardStore
    private let panel: NSPanel
    private var geometry: NotchGeometry
    private var hostingView: NSHostingView<NotchRootView>?
    private var pointerTimer: Timer?
    private var menuBarTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var activityObserver: AnyCancellable?
    private var pointerInside = false
    private var resizeMonitor: Any?
    private var resizeOrigin: (point: CGPoint, rightWidth: CGFloat, detailWidth: CGFloat,
                               compactHeight: CGFloat, extraHeight: Double, expanded: Bool)?
    private var resizeCursor = false

    init(store: DashboardStore) {
        self.store = store
        let screen = NSScreen.main ?? NSScreen.screens[0]
        geometry = NotchGeometry(screen: screen).fittingLayout(rows: store.topContent.map { $0.map(\.text) },
            hasDisclosure: store.canExpandConversations, preferences: store.preferences)
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
        menuBarTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.geometry.isCapsule else { return }
                self.refreshScreen()
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshScreen() } }
        activityObserver = store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshScreen() }
        resizeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            var consumed = false
            MainActor.assumeIsolated {
                guard let self else { return }
                consumed = self.handleResize(event) == nil
            }
            return consumed ? nil : event
        }
    }

    private func handleResize(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel else { return event }
        if event.type == .leftMouseDown && event.modifierFlags.contains([.control, .option]) {
            resizeOrigin = (NSEvent.mouseLocation, geometry.rightWingWidth, geometry.expandedWidth,
                geometry.compactHeight, store.preferences.extraDetailHeight, store.showHoverDetails || store.listExpanded)
            return nil
        }
        guard let origin = resizeOrigin else { return event }
        if event.type == .leftMouseUp { resizeOrigin = nil; return nil }
        guard event.type == .leftMouseDragged else { return event }
        let delta = NSEvent.mouseLocation
        let width = delta.x - origin.point.x
        let height = origin.point.y - delta.y
        var preferences = store.preferences
        if origin.expanded {
            preferences.preferredDetailWidth = max(320, origin.detailWidth + width)
            preferences.extraDetailHeight = min(300, max(0, origin.extraHeight + height))
        } else {
            preferences.preferredActivityWidth = max(28, origin.rightWidth + width)
            preferences.preferredCompactHeight = max(12, origin.compactHeight + height)
        }
        store.preferences = preferences
        return nil
    }

    private func refreshScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let updated = NotchGeometry(screen: screen).fittingLayout(rows: store.topContent.map { $0.map(\.text) },
            hasDisclosure: store.canExpandConversations, preferences: store.preferences)
        guard geometry != updated else { return }
        geometry = updated
        panel.setFrame(geometry.frame, display: true)
        hostingView?.rootView = NotchRootView(store: store, geometry: geometry)
        updatePointer()
    }

    private func updatePointer() {
        let point = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let detailHeight = store.listExpanded ? geometry.listDetailHeight : geometry.detailHeight
        let hovering = store.showsAnnouncement || geometry.topContains(point, hasActivity: store.hasTopContent)
            || ((store.showHoverDetails || store.listExpanded)
                && geometry.detailContains(point, height: detailHeight))
        if hovering != pointerInside {
            pointerInside = hovering
            store.setHover(hovering)
        }
        let clickable = (store.canExpandConversations && geometry.disclosureContains(point))
            || ((store.showHoverDetails || store.listExpanded)
                && geometry.detailContains(point, height: detailHeight))
        let canResize = NSEvent.modifierFlags.contains([.control, .option]) && (hovering || pointerInside)
        if canResize && !resizeCursor { NSCursor.crosshair.set() }
        if !canResize && resizeCursor { NSCursor.arrow.set() }
        resizeCursor = canResize
        panel.ignoresMouseEvents = !(clickable || canResize || resizeOrigin != nil)
    }

    func stop() {
        pointerTimer?.invalidate()
        menuBarTimer?.invalidate()
        activityObserver?.cancel()
        if let resizeMonitor { NSEvent.removeMonitor(resizeMonitor) }
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

struct NotchSurface: Shape {
    var width: CGFloat
    let compactWidth: CGFloat
    let compactHeight: CGFloat
    var visibleDepth: CGFloat
    let isCapsule: Bool

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, visibleDepth) }
        set { width = newValue.first; visibleDepth = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let depth = max(0, visibleDepth)
        let center = rect.midX
        let bottom = compactHeight + depth
        let corner: CGFloat = isCapsule ? min(17, compactHeight / 2) : 17

        if isCapsule {
            return Path(roundedRect: CGRect(x: center - width / 2, y: 0, width: width, height: bottom),
                        cornerRadius: corner)
        }

        func surface(width: CGFloat, top: CGFloat, bottom: CGFloat, corner: CGFloat) -> Path {
            let left = center - width / 2
            let right = center + width / 2
            var path = Path()
            path.move(to: CGPoint(x: left, y: top))
            path.addLine(to: CGPoint(x: right, y: top))
            path.addLine(to: CGPoint(x: right, y: bottom - corner))
            path.addQuadCurve(to: CGPoint(x: right - corner, y: bottom),
                control: CGPoint(x: right, y: bottom))
            path.addLine(to: CGPoint(x: left + corner, y: bottom))
            path.addQuadCurve(to: CGPoint(x: left, y: bottom - corner),
                control: CGPoint(x: left, y: bottom))
            path.addLine(to: CGPoint(x: left, y: top))
            path.closeSubpath()
            return path
        }

        var path = surface(width: compactWidth, top: 0, bottom: compactHeight, corner: 17)
        if depth > 0 {
            // The details may expand below the menu bar without widening its top.
            path.addPath(surface(width: max(width, compactWidth), top: compactHeight,
                bottom: bottom, corner: min(17, depth / 2)))
        }
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
        let hasActivity = store.hasTopContent
        let compactWidth = geometry.compactWidth(hasActivity: hasActivity)
        let rightWidth = geometry.isCapsule && !hasActivity ? 0 : geometry.rightWingWidth
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if store.preferences.showQuota {
                    QuotaCompactView(store: store, geometry: geometry)
                        .frame(width: geometry.leftWingWidth, height: geometry.compactHeight)
                } else if geometry.isCapsule && !hasActivity {
                    Image(systemName: "ellipsis").frame(width: geometry.leftWingWidth, height: geometry.compactHeight)
                }
                Color.clear.frame(width: geometry.gapWidth, height: geometry.compactHeight)
                ThreadCompactView(store: store, geometry: geometry)
                    .frame(width: rightWidth, height: geometry.compactHeight)
            }
            .frame(width: compactWidth, height: geometry.compactHeight)
            .clipped()
            .overlay(alignment: store.preferences.showQuota ? .leading : .trailing) {
                if store.hasUnseenReset {
                    Circle().fill(Visual.accent).frame(width: 5, height: 5).padding(.horizontal, 4)
                        .accessibilityLabel("Novo reset ainda não visto")
                }
            }

            CenteredDetailView(store: store, height: detailHeight, contentWidth: geometry.expandedWidth - 32,
                refreshButtonX: geometry.toolbarRefreshCenterX(hasActivity: hasActivity))
                .frame(width: geometry.expandedWidth, height: detailHeight)
                .frame(height: visibleDepth, alignment: .top)
                .clipped()

            Spacer(minLength: 0)
        }
        .frame(width: geometry.envelopeWidth, height: geometry.envelopeHeight, alignment: .top)
        .foregroundStyle(Visual.primary)
        .background(alignment: .top) {
            NotchSurface(
                width: expanded ? geometry.expandedWidth : compactWidth,
                compactWidth: compactWidth,
                compactHeight: geometry.compactHeight,
                visibleDepth: visibleDepth,
                isCapsule: geometry.isCapsule
            )
            .fill(.black)
            .frame(width: geometry.envelopeWidth, height: geometry.envelopeHeight)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: visibleDepth)
        .animation(geometry.isCapsule ? .spring(response: 0.42, dampingFraction: 0.84) : nil, value: compactWidth)
    }
}

private struct QuotaCompactView: View {
    @ObservedObject var store: DashboardStore
    let geometry: NotchGeometry

    var body: some View {
        Group {
            if geometry.isCapsule {
                capsuleQuota
            } else {
                notchedQuota
            }
        }
        .animation(.easeInOut(duration: 0.35), value: remainingFraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Franquia semanal do Codex: " + percentage + " restante")
    }

    private var capsuleQuota: some View {
        HStack(spacing: 8) {
            Text(percentage)
                .font(.system(size: geometry.capsuleQuotaFontSize, weight: .semibold))
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
                .contentTransition(.numericText())

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Visual.muted.opacity(0.34))
                    Capsule().fill(Visual.accent)
                        .frame(width: proxy.size.width * remainingFraction)
                }
            }
            .frame(width: 24, height: max(4, geometry.compactHeight * 0.18))
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    private var notchedQuota: some View {
        ZStack {
            Circle()
                .stroke(Visual.muted.opacity(0.34), lineWidth: geometry.quotaStrokeWidth)
            Circle()
                .trim(from: 0, to: remainingFraction)
                .stroke(Visual.accent, style: StrokeStyle(lineWidth: geometry.quotaStrokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(percentage)
                .font(.system(size: percentage == "100%" ? 8 : 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
        }
        .frame(width: geometry.quotaDiameter, height: geometry.quotaDiameter)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 12)
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
    let geometry: NotchGeometry

    var body: some View {
        Group {
            if geometry.isCapsule {
                HStack(spacing: 7) {
                    ForEach(store.topContent.flatMap { $0 }) { cell in cellView(cell, size: geometry.capsuleActivityFontSize) }
                    if store.canExpandConversations { disclosureButton(height: geometry.compactHeight) }
                }
                .padding(.horizontal, 8)
            } else if store.hasTopContent {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(store.topContent.enumerated()), id: \.offset) { index, cells in
                        HStack(spacing: 5) {
                            ForEach(cells) { cell in
                                cellView(cell, size: min(store.topContent.count == 1 ? 10 : index == 0 ? 9.2 : 8,
                                    max(6, (geometry.compactHeight - 2) / CGFloat(store.topContent.count) - 2)))
                            }
                            if index == 0 && store.canExpandConversations { disclosureButton(height: 14) }
                        }
                    }
                }.padding(.leading, 6).padding(.trailing, 8)
            } else if !store.preferences.showQuota {
                Image(systemName: "ellipsis").font(.system(size: 11))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cellView(_ cell: DashboardCell, size: CGFloat) -> some View {
        Group {
            if cell.field == .tiboAnnouncement { TiboAnnouncementView(store: store, size: min(20, size + 6)) }
            else { Text(cell.text).font(.system(size: size, weight: .medium)).lineLimit(1)
                .help(cell.field == .tokenRate || cell.field == .outputTokenRate ? store.tokenRateDescription(for: cell.field) : cell.text) }
        }
            .truncationMode(.tail).minimumScaleFactor(0.75)
            .foregroundStyle(cell.field == .tokenRate || cell.field == .outputTokenRate || cell.field == .effort ? Visual.accent : Visual.primary)
            .layoutPriority(cell.field == .conversation || cell.field == .project ? 0 : 1)
    }

    private func disclosureButton(height: CGFloat) -> some View {
        Button { store.toggleThreads() } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .rotationEffect(.degrees(store.listExpanded ? 180 : 0))
                .frame(width: 16, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Visual.primary)
        .accessibilityLabel(store.listExpanded ? "Ocultar outras conversas" : "Mostrar outras conversas")
        .help(store.listExpanded ? "Ocultar outras conversas" : "Mostrar outras conversas")
    }
}

private struct CenteredDetailView: View {
    @ObservedObject var store: DashboardStore
    let height: CGFloat
    let contentWidth: CGFloat
    let refreshButtonX: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 8) {
                ForEach(Array(store.preferences.detailRows.enumerated()), id: \.offset) { _, fields in
                    if !fields.isEmpty {
                        HStack(alignment: .center, spacing: 12) {
                            ForEach(fields) { field in
                                detailField(field, at: context.date)
                                    .frame(width: max(1, (contentWidth - CGFloat(fields.count - 1) * 12) / CGFloat(fields.count)),
                                        height: DashboardPreferences.detailRowHeight(fields) - (fields.contains(.lastReset) ? 4 : 0),
                                        alignment: .center)
                            }
                        }
                        .padding(.top, fields.contains(.lastReset) ? 4 : 0)
                        .frame(height: DashboardPreferences.detailRowHeight(fields))
                    }
                }
                if store.showNewResetInPanel && !store.preferences.detailRows.joined().contains(.lastReset) {
                    detailField(.lastReset, at: context.date).frame(height: 20)
                }
                if store.listExpanded && store.canExpandConversations {
                    VStack(spacing: 3) {
                        Text("OUTRAS CONVERSAS · \(store.rootThreads.count - 1)").detailHeading()
                        ScrollView(.vertical, showsIndicators: store.rootThreads.count > 3) {
                            VStack(spacing: 3) {
                                ForEach(store.rootThreads.dropFirst()) { thread in
                                    HStack {
                                        Text(thread.title).fontWeight(.medium).truncationMode(.tail)
                                        Spacer(minLength: 8)
                                        Text(Format.model(thread.model) + " · " + Format.effort(thread.effort))
                                    }
                                    .font(.system(size: 9)).foregroundStyle(Visual.secondary).lineLimit(1)
                                }
                            }
                        }.frame(height: 28)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: contentWidth)
            .padding(.top, 32)
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            .multilineTextAlignment(.center)
            .overlay(alignment: .topLeading) {
                forecastRefreshButton.offset(x: refreshButtonX - 14, y: 2)
            }
            .overlay(alignment: .topTrailing) {
                Button { store.onOpenSettings?() } label: {
                    Image(systemName: "gearshape").font(.system(size: 10, weight: .medium))
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(Visual.muted)
                .accessibilityLabel("Abrir configurações").help("Configurações do Codex Reset")
                .modifier(PointingHandCursor())
                .offset(x: -(refreshButtonX - 14), y: 2)
            }
            .overlay(alignment: .top) {
                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power").font(.system(size: 10, weight: .medium))
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(Visual.muted)
                .accessibilityLabel("Fechar Codex Reset").help("Fechar Codex Reset")
                .modifier(PointingHandCursor()).padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func detailField(_ field: DashboardField, at now: Date) -> some View {
        if field == .tiboAnnouncement {
            TiboAnnouncementView(store: store).frame(maxWidth: .infinity)
        } else if field == .lastReset {
            HStack(spacing: 5) {
                Image(systemName: store.showNewResetInPanel ? "sparkle" : "clock.arrow.circlepath")
                Text("\(store.showNewResetInPanel ? "Novo reset" : "Último reset") · \(store.text(for: field, at: now) ?? "—")")
            }
            .font(.system(size: 10, weight: store.showNewResetInPanel ? .semibold : .regular))
            .foregroundStyle(store.showNewResetInPanel ? Visual.accent : Visual.secondary)
            .help(store.lastResetNotice.map { "Franquia renovada em " + $0.date.formatted(date: .abbreviated, time: .shortened) } ?? "Aguardando dados da conta")
        } else {
            VStack(spacing: 3) {
                Text(field.label.uppercased()).detailHeading()
                Text(store.text(for: field, at: now) ?? "Sem atividade")
                    .font(.system(size: 12, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, minHeight: field == .extraReset || field == .weeklyReset ? 32 : 18)
                if field == .extraReset {
                    Text(extraCaption(at: now)).font(.system(size: 10)).foregroundStyle(Visual.secondary).lineLimit(1)
                } else if field == .tokenRate || field == .outputTokenRate {
                    Text(field == .tokenRate ? "Entrada + saída · cache incluído" : "Média de saída")
                        .font(.system(size: 9)).foregroundStyle(Visual.secondary).lineLimit(1).minimumScaleFactor(0.75)
                } else if field == .weeklyReset {
                    Text("Informado pelo Codex").font(.system(size: 10)).foregroundStyle(Visual.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity)
        }
    }

    private var forecastRefreshButton: some View {
        Button { store.refreshForecast() } label: {
            ZStack {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(store.isRefreshingForecast ? 0 : 1)
                if store.isRefreshingForecast {
                    ProgressView().controlSize(.mini)
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Visual.accent)
        .disabled(store.isRefreshingForecast)
        .accessibilityLabel(store.isRefreshingForecast ? "Atualizando previsão" : "Atualizar previsão do reset extra")
        .help(store.forecastError.map { "Falha na última consulta: \($0) Clique para tentar novamente." }
            ?? "Consultar agora a previsão do reset extra")
        .modifier(PointingHandCursor())
    }

    private func extraHeadline(at now: Date) -> String {
        guard let forecast = store.forecast else {
            return store.isRefreshingForecast || store.forecastError == nil ? "Buscando previsão…" : "Previsão indisponível"
        }
        return forecast.presentation(at: now).headline
    }

    private func extraCaption(at now: Date) -> String {
        guard let forecast = store.forecast else {
            return store.isRefreshingForecast || store.forecastError == nil ? "Histórico em atualização" : "Fonte indisponível"
        }
        return forecast.presentation(at: now).caption
    }

    private func weeklyHeadline(at now: Date) -> String {
        guard let reset = store.usage?.weeklyWindow?.resetsAt else {
            return "Horário ainda indisponível"
        }
        guard let countdown = ResetCountdown.remaining(until: reset, at: now) else {
            return "Aguardando atualização"
        }
        return "Em \(countdown)"
    }

}

private struct PointingHandCursor: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                guard inside != hovering else { return }
                hovering = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                if hovering {
                    NSCursor.pop()
                    hovering = false
                }
            }
    }
}

private extension View {
    func detailHeading() -> some View {
        font(.system(size: 8, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(Visual.muted)
    }
}

enum Format {
    static func tokenRate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "— tok/s" }
        if value < 1 { return "<1 tok/s" }
        if value >= 1_000_000 { return "~" + String(format: "%.1fM", value / 1_000_000).replacingOccurrences(of: ".", with: ",") + " tok/s" }
        if value >= 1_000 { return "~" + String(format: "%.1fk", value / 1_000).replacingOccurrences(of: ".", with: ",") + " tok/s" }
        return "~\(Int(min(value.rounded(), 999_999_999))) tok/s"
    }
    static func shortModel(_ value: String) -> String {
        let pieces = value.split(separator: "-")
        return pieces.count > 1 && pieces[0].lowercased() == "gpt" ? String(pieces[1]) : value
    }

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

}
