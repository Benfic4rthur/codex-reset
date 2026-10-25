import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: DashboardStore
    private var window: NSWindow?
    init(store: DashboardStore) { self.store = store }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 620, height: 760),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Configurações — Codex Reset"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: DashboardSettingsView(store: store) { [weak self] in self?.hide() })
            window.center()
            self.window = window
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
    let hide: () -> Void
    @State private var dragged: DashboardField?
    @State private var source: LayoutPosition?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Monte o seu painel").font(.title2.bold())
                    Text("Arraste os campos para escolher a posição de cada informação.").foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Button("Padrão") { store.preferences = DashboardPreferences() }
                        Button("Só porcentagem") { store.preferences.showQuota = true; store.preferences.topRows = [[], []] }
                        Button("Agente e tok/s") {
                            store.preferences.agentOnly()
                            store.preferences.topRows = [[.tokenRate], [.model, .effort]]
                        }
                        Button("Conversa + tok/s") {
                            store.preferences.topRows = [[.conversation, .tokenRate], [.model, .effort]]
                        }
                    }
                    layoutEditor
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Ajuste de tamanho").font(.headline)
                            Spacer()
                            Button("Ajustar automaticamente") {
                                store.preferences.preferredActivityWidth = nil
                                store.preferences.preferredDetailWidth = nil
                                store.preferences.preferredCompactHeight = nil
                                store.preferences.extraDetailHeight = 0
                            }
                        }
                        dimension("Largura da direita", value: Binding(get: { store.preferences.preferredActivityWidth ?? 160 },
                            set: { store.preferences.preferredActivityWidth = $0 }), range: 28...320)
                        dimension("Largura do painel aberto", value: Binding(get: { store.preferences.preferredDetailWidth ?? 380 },
                            set: { store.preferences.preferredDetailWidth = $0 }), range: 320...900)
                        dimension("Altura da barra", value: Binding(get: { store.preferences.preferredCompactHeight ?? 36 },
                            set: { store.preferences.preferredCompactHeight = $0 }), range: 12...40)
                        dimension("Espaço extra embaixo", value: $store.preferences.extraDetailHeight, range: 0...240)
                        Text("Ctrl + Option + arrastar no monitor também ajusta o tamanho. No painel aberto, ajusta os detalhes; na barra, ajusta o topo. A altura do topo respeita o espaço da barra de menus da tela.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Porcentagem e barra de franquia no lado esquerdo", isOn: $store.preferences.showQuota)
                        Toggle("Permitir expandir a lista de outras conversas", isOn: $store.preferences.showConversations)
                        Toggle("Nome curto do modelo (ex.: 6.1)", isOn: $store.preferences.compactModelName)
                        Toggle("Destacar novo reset nas três primeiras aberturas", isOn: $store.preferences.highlightNewReset)
                    }
                    Text("Tokens/s é uma estimativa do consumo de entrada e saída, atualizada a cada 5 segundos. Não mede a velocidade de geração. O agente principal é o de maior esforço entre as conversas ativas.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 20).padding(.bottom, 20)
            }
            Divider()
            HStack {
                Text("Salvo automaticamente neste Mac.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Ocultar na barra de menus", action: hide).keyboardShortcut(.defaultAction)
            }.padding(16)
        }.frame(width: 620, height: 760)
    }

    private var layoutEditor: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Campos").font(.headline)
                Text("Arraste para o desenho").font(.caption).foregroundStyle(.secondary)
                ForEach(DashboardField.allCases) { field in
                    HStack(spacing: 5) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                        Text(field.label).lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                    .onDrag { dragged = field; source = nil; return NSItemProvider(object: field.rawValue as NSString) }
                }
            }.frame(width: 145)
            VStack(alignment: .leading, spacing: 8) {
                Text("Seu notch").font(.headline)
                VStack(spacing: 12) {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(spacing: 4) {
                            Text(store.preferences.showQuota ? store.text(for: .quota) ?? "—%" : "")
                                .font(.system(size: 18, weight: .semibold)).foregroundStyle(.mint)
                            if store.preferences.showQuota {
                                Capsule().fill(.mint).frame(width: 30, height: 3)
                            }
                        }.frame(width: 44)
                        VStack {
                            Circle().fill(Color.white.opacity(0.15)).frame(width: 7, height: 7)
                            Text("câmera").font(.system(size: 7)).foregroundStyle(.secondary)
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
                Text("Cada área é uma linha. Arraste os campos já colocados para reorganizar; use × para remover. O menu + também adiciona campos.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Em telas sem notch, as linhas de cima são reunidas na barra de menus.")
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

    private func layoutRow(_ region: LayoutRegion, row: Int) -> some View {
        let rows = region == .top ? store.preferences.topRows : store.preferences.detailRows
        let fields = rows.indices.contains(row) ? rows[row] : []
        return HStack(spacing: 6) {
            Text("\(row + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 12)
            HStack(spacing: 5) {
                if fields.isEmpty {
                    Text("Arraste campos para esta linha").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(fields.enumerated()), id: \.element) { index, field in
                    HStack(spacing: 4) {
                        Text(field.label).lineLimit(1)
                        Button {
                            store.preferences.remove(at: LayoutPosition(region: region, row: row, index: index))
                        } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Remover \(field.label) da linha \(row + 1)")
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
                    Button(field.label) { store.preferences.place(field, in: region, row: row) }
                }
            } label: { Image(systemName: "plus") }
            .menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel("Adicionar campo à linha \(row + 1) \(region == .top ? "de cima" : "de baixo")")
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
