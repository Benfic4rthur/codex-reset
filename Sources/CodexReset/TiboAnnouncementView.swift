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
        .buttonStyle(.plain).accessibilityLabel(store.tr("Ler último anúncio de reset do Tibo"))
        .help(store.tr("Clique na foto para ler o último anúncio de reset."))
        .onHover { inside in
            closeWork?.cancel()
            if !inside && presented { scheduleClose() }
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
                    Text(store.tr(store.forecast?.latestAnnouncement?.isSourceSummary == true
                        ? "Resumo do último reset" : "Último anúncio de reset")).font(.caption).foregroundStyle(.secondary)
                        .help(store.forecast?.latestAnnouncement?.isSourceSummary == true
                            ? store.tr("Resumo fornecido pelo site; o link abre a referência no X.") : store.tr("Último anúncio de reset"))
                }
                Spacer()
            }
            if let post = store.forecast?.latestAnnouncement {
                Text(store.language.date(post.date)).font(.caption).foregroundStyle(.secondary)
                if !store.language.needsAnnouncementTranslation {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(post.readableText).font(.system(size: 14)).textSelection(.enabled)
                        Text(store.tr(post.isSourceSummary ? "Texto da fonte · inglês" : "Tradução automática · português"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else if #available(macOS 15.0, *) {
                    TranslatedPost(post: post, store: store, language: store.language)
                        .id(store.language.translationKey(for: post))
                } else {
                    Text(store.tr("A tradução integrada requer macOS 15 ou posterior.")).font(.caption).foregroundStyle(.secondary)
                    Text(post.readableText).font(.system(size: 13)).textSelection(.enabled)
                }
                if !post.links.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(post.links.enumerated()), id: \.element) { index, url in
                            Link(store.tr("Link %d ↗", index + 1), destination: url)
                                .font(.caption).padding(.horizontal, 8).padding(.vertical, 5)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5)).help(url.absoluteString)
                        }
                        Link(store.tr(post.isSourceSummary ? "Referência no X ↗" : "Anúncio original ↗"), destination: post.url)
                            .font(.caption).padding(.horizontal, 8).padding(.vertical, 5)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    }
                } else {
                    Link(store.tr(post.isSourceSummary ? "Referência no X ↗" : "Anúncio original ↗"), destination: post.url).font(.caption)
                }
            } else {
                Text(store.isRefreshingForecast ? store.tr("Buscando o anúncio…") : store.tr("Anúncio ainda indisponível."))
                    .foregroundStyle(.secondary)
                Button(store.tr("Atualizar")) { store.refreshForecast() }
            }
        }.padding(18).frame(width: 370)
        .environment(\.locale, store.language.locale)
    }
}

@available(macOS 15.0, *)
private struct TranslatedPost: View {
    let post: ResetPost
    @ObservedObject var store: DashboardStore
    let language: AppLanguage
    @State private var failed = false
    @State private var configuration: TranslationSession.Configuration

    init(post: ResetPost, store: DashboardStore, language: AppLanguage) {
        self.post = post
        self.store = store
        self.language = language
        _configuration = State(initialValue: TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: language.rawValue)))
    }

    private var cacheKey: String { language.translationKey(for: post) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let translated = store.translatedPosts[cacheKey] {
                Text(translated).font(.system(size: 14)).textSelection(.enabled)
                Text(store.tr("Tradução automática · português")).font(.caption2).foregroundStyle(.secondary)
            } else if failed {
                Text(store.tr("Não foi possível traduzir agora. Confira os idiomas de tradução deste Mac.")).font(.caption).foregroundStyle(.secondary)
                Text(post.readableText).font(.system(size: 13)).textSelection(.enabled)
                Button(store.tr("Tentar traduzir")) { failed = false; configuration.invalidate() }
            } else {
                ProgressView(store.tr("Traduzindo para português…")).controlSize(.small)
            }
        }
        .translationTask(configuration) { session in
            guard store.translatedPosts[cacheKey] == nil else { return }
            do {
                let response = try await session.translate(post.readableText)
                store.translatedPosts[cacheKey] = response.targetText
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}
