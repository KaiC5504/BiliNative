import SwiftUI
import BiliAPI
import Danmaku

/// The account's 弹幕屏蔽词, grouped by kind, with an add field and swipe to delete. In landscape it is a page of
/// the side panel (`.panel`, dark); in portrait it is pushed onto the navigation stack (`.page`).
struct BlockWordsView: View {
    enum Appearance { case panel, page }

    let appearance: Appearance
    var onBack: (() -> Void)? = nil
    var onNeedLogin: () -> Void = {}

    @Environment(AppEnvironment.self) private var env
    @State private var kind: BlockRule.Kind = .keyword
    @State private var text = ""
    @State private var busy = false
    @State private var message: String?
    @FocusState private var focused: Bool

    private struct KindEntry: Identifiable {
        let kind: BlockRule.Kind
        let title: String
        let prompt: String
        var id: Int { kind.rawValue }
    }

    private static let kinds = [
        KindEntry(kind: .keyword, title: "关键词", prompt: "输入要屏蔽的关键词"),
        KindEntry(kind: .regex, title: "正则", prompt: "输入正则表达式"),
        KindEntry(kind: .user, title: "用户", prompt: "输入用户 UID"),
    ]

    private var store: BlockRuleStore { env.blockRules }
    private var dark: Bool { appearance == .panel }
    private var primary: Color { dark ? Theme.panelText : Theme.text }
    private var secondary: Color { dark ? Theme.panelSecondary : Theme.secondaryText }
    private var rowFill: Color { dark ? Theme.panelCard : .white }

    var body: some View {
        VStack(spacing: 0) {
            if dark { panelHeader }
            list
        }
        .background { if !dark { Theme.pageGrey.ignoresSafeArea() } }
        .navigationTitle("弹幕屏蔽词")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(dark ? .hidden : .visible, for: .navigationBar)
        .environment(\.colorScheme, dark ? .dark : .light)
        .tint(Theme.pink)
        .toast($message)
        .task { await store.refresh() }
    }

    private var panelHeader: some View {
        PanelHeader(title: "弹幕屏蔽词", back: onBack)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }

    private var list: some View {
        List {
            Section {
                VStack(spacing: 0) {
                    kindPicker
                    Rectangle()
                        .fill(Theme.DanmakuPanel.hairline.opacity(dark ? 1 : 0.4))
                        .frame(height: 0.5)
                    inputRow
                        .padding(.horizontal, 16)
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(rowFill)
            }
            ForEach(Self.kinds) { group in
                let rules = store.rules.filter { $0.kind == group.kind }
                if !rules.isEmpty {
                    Section {
                        ForEach(rules, id: \.id) { rule in
                            ruleRow(rule)
                                .listRowBackground(rowFill)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) { delete(rule) } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        Text("\(group.title) · \(rules.count)")
                            .font(.system(size: 12))
                            .foregroundStyle(secondary)
                            .textCase(nil)
                    }
                }
            }
            if store.rules.isEmpty {
                Section {
                    Text("还没有屏蔽词，添加后会同步到你的哔哩哔哩账号")
                        .font(.system(size: 13))
                        .foregroundStyle(secondary)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // insetGrouped keeps 16 pt at each side; in the panel the cards should span its width like the settings
        // cards do, so the list is widened by the same amount.
        .environment(\.horizontalSizeClass, .compact)
        .padding(.horizontal, dark ? -16 : 0)
        .animation(.smooth(duration: 0.25), value: store.rules)
    }

    // MARK: rows

    private var kindPicker: some View {
        HStack(spacing: 0) {
            ForEach(Self.kinds) { entry in
                if entry.id != Self.kinds.first?.id {
                    Rectangle()
                        .fill(secondary.opacity(0.4))
                        .frame(width: 1, height: 12)
                }
                Button {
                    kind = entry.kind
                } label: {
                    Text(entry.title)
                        .font(.system(size: 14, weight: entry.kind == kind ? .medium : .regular))
                        .foregroundStyle(entry.kind == kind ? Theme.pink : primary)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(entry.kind == kind ? .isSelected : [])
            }
        }
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            TextField("", text: $text,
                      prompt: Text(Self.kinds.first { $0.kind == kind }?.prompt ?? "").foregroundStyle(secondary))
                .font(.system(size: 14))
                .foregroundStyle(primary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(kind == .user ? .numberPad : .default)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit(add)
            Button(action: add) {
                Text("添加")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Theme.pink.opacity(canAdd ? 1 : 0.4), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
        }
        .frame(minHeight: 40)
    }

    private func ruleRow(_ rule: BlockRule) -> some View {
        Text(rule.kind == .user ? "UID 哈希 \(rule.filter)" : rule.filter)
            .font(.system(size: 14))
            .foregroundStyle(primary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
    }

    // MARK: actions

    private var canAdd: Bool {
        !busy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        guard canAdd else { return }
        guard case .loggedIn = env.account else {
            onNeedLogin()
            return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await store.add(kind, filter: text)
                text = ""
                focused = false
            } catch is CancellationError {
                return
            } catch {
                report(error, fallback: "添加失败，请稍后重试")
            }
        }
    }

    private func delete(_ rule: BlockRule) {
        Task {
            do {
                try await store.delete(rule)
            } catch is CancellationError {
                return
            } catch {
                report(error, fallback: "删除失败，请稍后重试")
            }
        }
    }

    private func report(_ error: Error, fallback: String) {
        if let error = error as? BlockRuleStore.RuleError {
            message = error.message
        } else if let error = error as? BiliError {
            switch error {
            case .api(-101, _): onNeedLogin()
            case .api(_, let reason) where !reason.isEmpty: message = reason
            default: message = fallback
            }
        } else {
            message = fallback
        }
    }
}
