import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: DashboardStore
    private var window: NSWindow?
    private var languageObserver: AnyCancellable?
    init(store: DashboardStore) { self.store = store }

    func show() {
        if window == nil {
            let height = min(1130, max(680, (NSScreen.main?.visibleFrame.height ?? 1000) - 50))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 980, height: height),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = store.tr("Configurações — Codex Reset")
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: DashboardSettingsView(store: store, height: height) { [weak self] in self?.hide() })
            window.center()
            self.window = window
            languageObserver = store.$preferences.map(\.appLanguage).removeDuplicates()
                .receive(on: DispatchQueue.main).sink { [weak window] language in
                    window?.title = language.text("Configurações — Codex Reset")
                }
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func hide() {
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }
    func windowWillClose(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
}

private struct DashboardSettingsView: View {
    @ObservedObject var store: DashboardStore
    let height: CGFloat
    let hide: () -> Void
    @State private var dragged: DashboardField?
    @State private var source: LayoutPosition?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.tr("Monte o seu painel")).font(.title2.bold())
                    Text(store.tr("Arraste os campos para escolher a posição de cada informação.")).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(20)
            HStack {
                Text(store.tr("Idioma")).font(.headline)
                Picker(store.tr("Idioma"), selection: Binding(get: { store.language }, set: { store.preferences.language = $0 })) {
                    ForEach(AppLanguage.allCases) { language in Text(language.name).tag(language) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 340)
                Spacer()
                Text(store.tr("Estilo da franquia")).font(.headline)
                Picker(store.tr("Estilo da franquia"), selection: Binding(
                    get: { store.preferences.selectedQuotaStyle }, set: { store.preferences.quotaStyle = $0 })) {
                    ForEach(QuotaStyle.allCases) { style in Text(store.tr(style.label)).tag(style) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 230)
                .help(store.tr("A porcentagem cresce ao abrir o painel, dentro do espaço disponível da barra."))
            }.padding(.horizontal, 20).padding(.bottom, 14)
            ViewThatFits(in: .vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    layoutSection
                    adjustmentsSection
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
                .fixedSize(horizontal: false, vertical: true)

                TabView {
                    layoutSection.padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).tabItem { Text(store.tr("Montar painel")) }
                    adjustmentsSection.padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).tabItem { Text(store.tr("Tamanho e opções")) }
                }
            }.frame(maxHeight: .infinity, alignment: .topLeading)
            Divider()
            HStack {
                Text(store.tr("Salvo automaticamente neste Mac.")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(store.tr("Ocultar na barra de menus"), action: hide).keyboardShortcut(.defaultAction)
            }.padding(16)
        }.frame(width: 980, height: height)
        .environment(\.locale, store.language.locale)
    }

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Button(store.tr("Padrão")) { store.restoreDefaultLayout() }
                        Button(store.tr("Só porcentagem")) { store.preferences.showQuota = true; store.preferences.topRows = [[], []] }
                        Button(store.tr("Agente e tok/s")) {
                            store.preferences.agentOnly()
                            store.preferences.topRows = [[.tokenRate], [.model, .effort]]
                        }
                        Button(store.tr("Conversa + tok/s")) {
                            store.preferences.topRows = [[.conversation, .tokenRate], [.model, .effort]]
                        }
                    }
                    HStack {
                        Text(store.tr("Arraste os campos para o desenho da tela")).font(.headline)
                        Spacer()
                        Button(store.preferences.classicEditor == true ? store.tr("Testar desenho novo") : store.tr("Editor anterior")) {
                            store.preferences.classicEditor = store.preferences.classicEditor != true
                        }
                    }
                    layoutEditor
        }
    }

    private var adjustmentsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(store.tr("Ajuste de tamanho")).font(.headline)
                            Spacer()
                            Button(store.tr("Ajustar automaticamente")) {
                                store.preferences.preferredActivityWidth = nil
                                store.preferences.preferredDetailWidth = nil
                                store.preferences.preferredCompactHeight = nil
                                store.preferences.extraDetailHeight = 0
                            }
                        }
                        dimension(store.tr("Largura da direita"), value: Binding(get: { store.preferences.preferredActivityWidth ?? 160 },
                            set: { store.preferences.preferredActivityWidth = $0 }), range: 28...320)
                        dimension(store.tr("Largura do painel aberto"), value: Binding(get: { store.preferences.preferredDetailWidth ?? 380 },
                            set: { store.preferences.preferredDetailWidth = $0 }), range: 320...900)
                        dimension(store.tr("Altura da barra"), value: Binding(get: { store.preferences.preferredCompactHeight ?? 36 },
                            set: { store.preferences.preferredCompactHeight = $0 }), range: 12...40)
                        dimension(store.tr("Espaço extra embaixo"), value: $store.preferences.extraDetailHeight, range: 0...240)
                        Text(store.tr("Ctrl + Option + arrastar no monitor também ajusta o tamanho. No painel aberto, ajusta os detalhes; na barra, ajusta o topo. A altura do topo respeita o espaço da barra de menus da tela."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(store.tr("Porcentagem e barra de franquia no lado esquerdo"), isOn: $store.preferences.showQuota)
                        Toggle(store.tr("Permitir expandir a lista de outras conversas"), isOn: $store.preferences.showConversations)
                        Toggle(store.tr("Nome curto do modelo (ex.: 6.1 Sol)"), isOn: $store.preferences.compactModelName)
                        Toggle(store.tr("Destacar novo reset nas três primeiras aberturas"), isOn: $store.preferences.highlightNewReset)
                    }
                    Text(store.tr("Total processado/s soma entrada e saída, incluindo o contexto em cache. Saída/s mostra só a saída. São médias entre registros do Codex, não velocidade instantânea nem franquia debitada; sem amostras recentes, mostram um traço. O agente principal é o de maior esforço entre as conversas ativas."))
                        .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var layoutEditor: some View {
        if store.preferences.classicEditor == true {
            classicLayoutEditor.frame(maxWidth: 680).frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.tr("Informações disponíveis")).font(.headline)
                    Text(store.tr("Arraste uma peça")).font(.caption).foregroundStyle(.secondary)
                    ForEach(DashboardField.allCases) { field in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                            Text(store.tr(field.label)).font(.system(size: 11, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .padding(6).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        .onDrag { dragged = field; source = nil; return NSItemProvider(object: field.rawValue as NSString) }
                    }
                }.frame(width: 165)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 0) {
                        Text(store.tr("ESQUERDA")).frame(width: 280)
                        Text(store.tr("CÂMERA FIXA")).frame(width: 100)
                        Text(store.tr("DIREITA · DUAS LINHAS")).frame(width: 280)
                    }
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.31, blue: 0.43), Color(red: 0.12, green: 0.17, blue: 0.26)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        VStack {
                            HStack(spacing: 10) {
                                Image(systemName: "apple.logo")
                                Spacer()
                                Image(systemName: "wifi")
                                Text("09:41")
                            }
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 14).frame(height: 24).background(.white.opacity(0.08))
                            Spacer()
                            RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.06))
                                .frame(width: 200, height: 110).overlay(alignment: .topLeading) {
                                    HStack(spacing: 4) {
                                        ForEach(0..<3) { _ in Circle().fill(.white.opacity(0.2)).frame(width: 5, height: 5) }
                                    }.padding(10)
                                }.padding(.trailing, 370).padding(.bottom, 28)
                        }
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                quotaPreview.frame(width: 280, height: 84)
                                VStack(spacing: 8) {
                                    Circle().fill(RadialGradient(colors: [.blue.opacity(0.55), .gray.opacity(0.2), .black], center: .center, startRadius: 1, endRadius: 7))
                                        .frame(width: 14, height: 14).overlay(Circle().stroke(.white.opacity(0.12)))
                                    Text(store.tr("Câmera do Mac")).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                                }.frame(width: 100, height: 84)
                                VStack(spacing: 4) {
                                    layoutRow(.top, row: 0)
                                    layoutRow(.top, row: 1)
                                }.padding(.horizontal, 8).frame(width: 280, height: 84)
                            }.frame(width: 660)
                            VStack(spacing: 9) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Spacer()
                                    Image(systemName: "power")
                                    Spacer()
                                    Image(systemName: "gearshape")
                                }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).padding(.horizontal, 20)
                                Text(store.tr("PAINEL ABERTO · TRÊS LINHAS")).font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
                                ForEach(0..<3) { row in layoutRow(.details, row: row) }
                            }.padding(16).frame(width: 660)
                        }
                        .frame(width: 660, height: 292, alignment: .top)
                        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 8)
                        .environment(\.colorScheme, .dark)
                    }
                    .frame(height: 350).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12)))
                    Text(store.tr("À esquerda fica a franquia. No meio, a câmera. À direita, as informações que você montar. A parte de baixo aparece quando o painel abre."))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(store.tr("Mova as peças para mudar a ordem, use × para remover e + para adicionar sem arrastar. Em telas sem notch, as linhas de cima ficam em uma linha na barra de menus."))
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
            }
        }
    }

    private var classicLayoutEditor: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(store.tr("Campos")).font(.headline)
                Text(store.tr("Arraste para o desenho")).font(.caption).foregroundStyle(.secondary)
                ForEach(DashboardField.allCases) { field in
                    HStack(spacing: 5) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                        Text(store.tr(field.label)).lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                    .onDrag { dragged = field; source = nil; return NSItemProvider(object: field.rawValue as NSString) }
                }
            }.frame(width: 145)
            VStack(alignment: .leading, spacing: 8) {
                Text(store.tr("Seu notch")).font(.headline)
                VStack(spacing: 12) {
                    HStack(alignment: .center, spacing: 8) {
                        quotaPreview.frame(width: 84)
                        VStack {
                            Circle().fill(Color.white.opacity(0.15)).frame(width: 7, height: 7)
                            Text(store.tr("câmera")).font(.system(size: 7)).foregroundStyle(.secondary)
                        }.frame(width: 30)
                        VStack(spacing: 5) {
                            layoutRow(.top, row: 0)
                            layoutRow(.top, row: 1)
                        }
                    }
                    Divider()
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Spacer()
                        Image(systemName: "power")
                        Spacer()
                        Image(systemName: "gearshape")
                    }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 12)
                    ForEach(0..<3) { row in layoutRow(.details, row: row) }
                }
                .padding(12).background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
                .environment(\.colorScheme, .dark)
                Text(store.tr("Cada área é uma linha. Arraste os campos já colocados para reorganizar; use × para remover. O menu + também adiciona campos."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(store.tr("Em telas sem notch, as linhas de cima são reunidas na barra de menus."))
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
        }
    }

    private func dimension(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label).font(.caption).frame(width: 145, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue)) pt").font(.caption.monospacedDigit()).frame(width: 42, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var quotaPreview: some View {
        if store.preferences.showQuota {
            let preview = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                menuBarHeight: 38, safeAreaTop: 38, notchGap: 180, notchCenterX: 720)
                .fittingLayout(rows: [], hasDisclosure: false, preferences: store.preferences)
            QuotaCompactView(store: store, geometry: preview, expanded: false)
                .frame(width: preview.leftWingWidth, height: preview.compactHeight).foregroundStyle(.white)
        }
    }

    private func layoutRow(_ region: LayoutRegion, row: Int) -> some View {
        let rows = region == .top ? store.preferences.topRows : store.preferences.detailRows
        let fields = rows.indices.contains(row) ? rows[row] : []
        return HStack(spacing: 6) {
            Text("\(row + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 12)
            HStack(spacing: 5) {
                if fields.isEmpty {
                    Text(store.tr("Arraste campos para esta linha")).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(fields.enumerated()), id: \.element) { index, field in
                    HStack(spacing: 4) {
                        Text(store.tr(field.label)).lineLimit(1)
                        Button {
                            store.preferences.remove(at: LayoutPosition(region: region, row: row, index: index))
                        } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel(store.tr("Remover %@ da linha %d", store.tr(field.label), row + 1))
                    }
                    .font(.system(size: 10, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .onDrag {
                        dragged = field
                        source = LayoutPosition(region: region, row: row, index: index)
                        return NSItemProvider(object: field.rawValue as NSString)
                    }
                    .onDrop(of: [UTType.text], delegate: LayoutFieldDrop(preferences: $store.preferences,
                        dragged: $dragged, source: $source, region: region, row: row, index: index))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .padding(.horizontal, 7)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4])))
            .onDrop(of: [UTType.text], delegate: LayoutFieldDrop(preferences: $store.preferences,
                dragged: $dragged, source: $source, region: region, row: row, index: nil))
            Menu {
                ForEach(DashboardField.allCases) { field in
                    Button(store.tr(field.label)) { store.preferences.place(field, in: region, row: row) }
                }
            } label: { Image(systemName: "plus") }
            .menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel(store.tr(region == .top ? "Adicionar campo à linha %d de cima" : "Adicionar campo à linha %d de baixo", row + 1))
        }
    }
}

private struct LayoutFieldDrop: DropDelegate {
    @Binding var preferences: DashboardPreferences
    @Binding var dragged: DashboardField?
    @Binding var source: LayoutPosition?
    let region: LayoutRegion
    let row: Int
    let index: Int?
    func validateDrop(info: DropInfo) -> Bool { dragged != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard let field = dragged else { return false }
        preferences.place(field, in: region, row: row, before: index, movingFrom: source)
        dragged = nil
        source = nil
        return true
    }
}
