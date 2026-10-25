import SwiftUI
import Translation

struct TiboAnnouncementView: View {
    @ObservedObject var store: DashboardStore
    var size: CGFloat = 23
    @State private var closeWork: DispatchWorkItem?
    @State private var presented = false

    var body: some View {
        Button { presented.toggle() } label: {
            ZStack(alignment: .bottomTrailing) {
                TiboAvatar(size: size)
                Text("𝕏").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                    .padding(1).background(.black, in: Circle()).offset(x: 3, y: 1)
            }.frame(width: size + 5, height: size + 3)
        }
        .buttonStyle(.plain).accessibilityLabel("Ler último anúncio de reset do Tibo")
        .help("Último anúncio de reset · traduzido para português")
        .onHover { inside in
            closeWork?.cancel()
            if inside { presented = true } else { scheduleClose() }
        }
        .onChange(of: presented) { _, value in store.showsAnnouncement = value }
        .onDisappear { closeWork?.cancel(); store.showsAnnouncement = false }
        .popover(isPresented: $presented, arrowEdge: .top) {
            AnnouncementCard(store: store)
                .onHover { inside in closeWork?.cancel(); if !inside { scheduleClose() } }
                .onExitCommand { presented = false }
        }
    }

    private func scheduleClose() {
        let work = DispatchWorkItem { presented = false }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }
}

private struct TiboAvatar: View {
    let size: CGFloat
    var body: some View {
        AsyncImage(url: URL(string: "https://codex-resets.com/thsottiaux-avatar.jpg")) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
        }
        .frame(width: size, height: size).clipShape(Circle())
    }
}

private struct AnnouncementCard: View {
    @ObservedObject var store: DashboardStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TiboAvatar(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tibo · @thsottiaux").font(.headline)
                    Text("Último anúncio de reset").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let post = store.forecast?.latestAnnouncement {
                Text(post.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                if #available(macOS 15.0, *) {
                    PortuguesePost(post: post, store: store)
                } else {
                    Text("A tradução integrada requer macOS 15 ou posterior.").font(.caption).foregroundStyle(.secondary)
                    Text(post.readableText).font(.system(size: 13)).textSelection(.enabled)
                }
                if !post.links.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(post.links.enumerated()), id: \.element) { index, url in
                            Link("Link \(index + 1) ↗", destination: url)
                                .font(.caption).padding(.horizontal, 8).padding(.vertical, 5)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5)).help(url.absoluteString)
                        }
                        Link("Anúncio original ↗", destination: post.url)
                            .font(.caption).padding(.horizontal, 8).padding(.vertical, 5)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    }
                } else {
                    Link("Anúncio original ↗", destination: post.url).font(.caption)
                }
            } else {
                Text(store.isRefreshingForecast ? "Buscando o anúncio…" : "Anúncio ainda indisponível.")
                    .foregroundStyle(.secondary)
                Button("Atualizar") { store.refreshForecast() }
            }
        }.padding(18).frame(width: 370)
    }
}

@available(macOS 15.0, *)
private struct PortuguesePost: View {
    let post: ResetPost
    @ObservedObject var store: DashboardStore
    @State private var error: String?
    @State private var configuration = TranslationSession.Configuration(
        source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "pt-BR"))

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let translated = store.translatedPosts[post.id] {
                Text(translated).font(.system(size: 14)).textSelection(.enabled)
                Text("Tradução automática · português").font(.caption2).foregroundStyle(.secondary)
            } else if let error {
                Text(error).font(.caption).foregroundStyle(.secondary)
                Text(post.readableText).font(.system(size: 13)).textSelection(.enabled)
                Button("Tentar traduzir") { self.error = nil; configuration.invalidate() }
            } else {
                ProgressView("Traduzindo para português…").controlSize(.small)
            }
        }
        .translationTask(configuration) { session in
            guard store.translatedPosts[post.id] == nil else { return }
            do {
                let response = try await session.translate(post.readableText)
                store.translatedPosts[post.id] = response.targetText
            } catch {
                self.error = "Não foi possível traduzir agora. Confira os idiomas de tradução deste Mac."
            }
        }
        .onChange(of: post.id) { _, _ in error = nil; configuration.invalidate() }
    }
}
