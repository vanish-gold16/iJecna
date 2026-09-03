import SwiftUI

struct NewsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            AuroraBackground()
            content
        }
        .navigationTitle("Aktuality")
        .task { await model.loadNews() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.news {
        case .idle, .loading:
            ProgressView().controlSize(.large)
        case .failed(let error):
            ErrorStateView(error: error) { Task { await model.loadNews(force: true) } }
        case .loaded(let articles, _):
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(articles) { article in
                        NavigationLink {
                            ArticleDetailView(article: article)
                        } label: {
                            ArticleCard(article: article)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 44)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .refreshable { await model.loadNews(force: true) }
        }
    }
}

struct ArticleCard: View {
    let article: Article

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(DateFormatter.jecnaShortDate.string(from: article.date))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accent)
                    if article.schoolOnly {
                        Label("Jen pro školu", systemImage: "lock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !article.attachments.isEmpty {
                        Label("\(article.attachments.count)", systemImage: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(article.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)

                Text(article.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Text(article.author)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
    }
}

struct ArticleDetailView: View {
    let article: Article

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(article.title)
                            .font(.title2.weight(.bold))

                        HStack(spacing: 10) {
                            Label(DateFormatter.jecnaShortDate.string(from: article.date), systemImage: "calendar")
                            Label(article.author, systemImage: "person")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Text(article.content)
                        .font(.body)

                    if !article.attachments.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader("Přílohy")
                            ContentCard {
                                VStack(spacing: 0) {
                                    ForEach(Array(article.attachments.enumerated()), id: \.element.id) { index, file in
                                        if index > 0 { Divider().padding(.leading, 52) }
                                        HStack(spacing: 12) {
                                            Image(systemName: file.symbolName)
                                                .font(.title3)
                                                .foregroundStyle(Theme.accent)
                                                .frame(width: 28)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(file.label)
                                                    .font(.subheadline)
                                                Text(file.fileExtension)
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                            }
                                            Spacer()
                                            Image(systemName: "arrow.down.circle")
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 11)
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 44)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .navigationTitle("Aktualita")
        .navigationBarTitleDisplayMode(.inline)
    }
}
