import SwiftUI
import BiliAPI

/// Sizes measured on 28 (3 px per point).
private enum HistoryMetrics {
    static let gutter: CGFloat = 12
    static let coverWidth: CGFloat = 136
    static let coverHeight: CGFloat = 76
    static let rowPadding: CGFloat = 12
    static let textGap: CGFloat = 9
    static let titleSize: CGFloat = 14
    static let metaSize: CGFloat = 13
    static let sectionSize: CGFloat = 16
    static let progressSize: CGFloat = 11
    static let barHeight: CGFloat = 2
}

/// 历史记录 (28): 视频 only, grouped by day, endless scroll.
struct HistoryView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: HistoryModel?
    @State private var showLogin = false

    private var loggedOut: Bool {
        switch env.account {
        case .loggedOut, .expired: return true
        case .loggedIn, .unknown: return model?.needsLogin == true
        }
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.card)
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showLogin) { LoginView() }
            .task {
                if model == nil { model = HistoryModel(client: env.client) }
                if let model, model.items.isEmpty, !loggedOut { await model.loadMore() }
            }
            .onChange(of: env.account) { _, account in
                guard case .loggedIn = account, let model, model.items.isEmpty || model.needsLogin else { return }
                Task { await model.reload() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if loggedOut {
            VStack(spacing: 16) {
                Text("登录后查看历史记录")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
                Button { showLogin = true } label: {
                    Text("登录")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.card)
                        .padding(.horizontal, 36)
                        .frame(height: 36)
                        .background(Theme.pink, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        } else if let model {
            if model.items.isEmpty {
                placeholder(model)
            } else {
                list(model)
            }
        }
    }

    @ViewBuilder
    private func placeholder(_ model: HistoryModel) -> some View {
        if let error = model.error {
            RetryMessage(message: error) { Task { await model.loadMore() } }
        } else if model.isEnd {
            Text("还没有看过视频")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)
        } else {
            ProgressView()
        }
    }

    private func list(_ model: HistoryModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.sections) { section in
                    Text(section.title)
                        .font(.system(size: HistoryMetrics.sectionSize))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, HistoryMetrics.gutter)
                        .padding(.top, 18)
                        .padding(.bottom, 6)
                    ForEach(section.items) { item in
                        HistoryRow(item: item, time: model.timeLabel(for: item))
                            .onTapGesture { env.navigator.open(HistoryModel.route(for: item)) }
                            .onAppear {
                                if item.id == model.items.last?.id, model.error == nil {
                                    Task { await model.loadMore() }
                                }
                            }
                    }
                }
                footer(model)
            }
        }
        .refreshable { await model.reload() }
    }

    @ViewBuilder
    private func footer(_ model: HistoryModel) -> some View {
        Group {
            if let error = model.error {
                RetryMessage(message: error) { Task { await model.loadMore() } }
            } else if model.isEnd {
                Text("没有更多了")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

private struct HistoryRow: View {
    let item: HistoryItem
    let time: String

    var body: some View {
        HStack(alignment: .top, spacing: HistoryMetrics.textGap) {
            cover
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.system(size: HistoryMetrics.titleSize))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    UPBadge()
                    Text(item.ownerName)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Image(systemName: HistoryModel.deviceSymbol(item.deviceKind))
                        .frame(width: 13)
                    Text(time)
                        .lineLimit(1)
                }
                .padding(.top, 5)
            }
            .font(.system(size: HistoryMetrics.metaSize))
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: HistoryMetrics.coverHeight)
        .padding(.vertical, HistoryMetrics.rowPadding)
        .padding(.trailing, HistoryMetrics.gutter)
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
        .padding(.leading, HistoryMetrics.gutter)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var cover: some View {
        RemoteImage(item.cover)
            .frame(width: HistoryMetrics.coverWidth, height: HistoryMetrics.coverHeight)
            .overlay(alignment: .bottomTrailing) {
                Text(HistoryModel.progressLabel(for: item))
                    .font(.system(size: HistoryMetrics.progressSize))
                    .monospacedDigit()
                    .foregroundStyle(Theme.onCover)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.coverShade, in: RoundedRectangle(cornerRadius: 4))
                    .padding(5)
            }
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geometry in
                    Theme.pink
                        .frame(width: geometry.size.width * HistoryModel.progressFraction(for: item))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(height: HistoryMetrics.barHeight)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
    }
}

/// A failed load, with a pink 重试 under the message.
struct RetryMessage: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text("重试")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.card)
                    .padding(.horizontal, 20)
                    .frame(height: Theme.Metrics.pillHeight)
                    .background(Theme.pink, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Metrics.gutter)
    }
}
