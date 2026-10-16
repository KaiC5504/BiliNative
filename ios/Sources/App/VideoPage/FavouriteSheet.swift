import SwiftUI
import Observation
import BiliAPI
import DevLog

extension Theme {
    enum Favourites {
        static let dim = Color.black.opacity(0.4)
        static let rowHeight: CGFloat = 58
        static let check: CGFloat = 21
        static let doneHeight: CGFloat = 40
        static let doneText = Color.white
        static let fieldHeight: CGFloat = 38
        /// Of the screen height, in portrait.
        static let sheetHeight: CGFloat = 0.62
        /// Bilibili refuses longer folder names.
        static let maxTitle = 20
        static let titleFont = Font.system(size: 15)
        static let countFont = Font.system(size: 12)
    }
}

/// The account's folders for one video: which hold it now, which the user has ticked, and new folders made here.
@MainActor
@Observable
final class FavouritesModel {
    enum Phase: Equatable {
        case loading, loaded, failed
    }

    private(set) var phase: Phase = .loading
    private(set) var folders: [FavFolder] = []
    private(set) var ticked: Set<Int64> = []
    /// The folders that held the video when the sheet opened.
    private(set) var original: Set<Int64> = []
    private(set) var creating = false
    var error: String?

    @ObservationIgnored private let client: BiliClient
    @ObservationIgnored private let aid: Int64
    @ObservationIgnored private let mid: () async -> Int64?

    init(client: BiliClient, aid: Int64, mid: @escaping () async -> Int64?) {
        self.client = client
        self.aid = aid
        self.mid = mid
    }

    func load() async {
        phase = .loading
        error = nil
        guard let mid = await mid() else {
            phase = .failed
            return
        }
        do {
            let list = try await client.favouriteFolders(mid: mid, aid: aid)
            folders = list
            original = Set(list.filter(\.contains).map(\.id))
            ticked = original
            phase = .loaded
        } catch {
            Logger.shared.warn(.api, "favourite folders failed", ["error": .init(String(describing: error))])
            phase = .failed
        }
    }

    func toggle(_ id: Int64) {
        if ticked.contains(id) {
            ticked.remove(id)
        } else {
            ticked.insert(id)
        }
    }

    /// The folders to add the video to and to take it out of, in list order.
    var change: (add: [Int64], remove: [Int64]) {
        let order = folders.map(\.id)
        return (order.filter { ticked.contains($0) && !original.contains($0) },
                order.filter { original.contains($0) && !ticked.contains($0) })
    }

    /// Makes the folder, lists it after the default one and ticks it.
    func create(title: String, isPrivate: Bool) async -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !creating else { return false }
        creating = true
        defer { creating = false }
        error = nil
        do {
            let folder = try await client.createFolder(title: title, isPrivate: isPrivate)
            folders.insert(folder, at: folders.firstIndex { !$0.isDefault } ?? folders.count)
            ticked.insert(folder.id)
            return true
        } catch {
            Logger.shared.warn(.api, "create folder failed", ["error": .init(String(describing: error))])
            self.error = (error as? BiliError).map(ActionsModel.message(for:)) ?? "网络连接失败，请检查网络后重试"
            return false
        }
    }

    /// What 完成 sends: only the difference from when the sheet opened.
    func apply(to actions: ActionsModel) async {
        let change = self.change
        await actions.applyFavourites(add: change.add, remove: change.remove, inAnyFolder: !ticked.isEmpty)
    }
}

/// 选择收藏夹: a light bottom sheet in portrait and the dark side panel in landscape. An overlay in the page, never a
/// presented controller.
struct FavouriteSheet: View {
    static let identifier = "panel.favourites"

    let actions: ActionsModel
    let model: FavouritesModel
    var onClose: () -> Void = {}

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                SidePanel(identifier: Self.identifier, dismiss: onClose) {
                    FavouriteList(model: model, palette: .dark, scrolls: false) {
                        done()
                        onClose()
                    }
                }
            } else {
                LightSheet(identifier: Self.identifier, height: geometry.size.height * Theme.Favourites.sheetHeight,
                           dismiss: onClose) { close in
                    FavouriteList(model: model, palette: .light, scrolls: true) {
                        done()
                        close()
                    }
                }
            }
        }
    }

    private func done() {
        let actions = self.actions
        let model = self.model
        Task { await model.apply(to: actions) }
    }
}

private struct FavouriteList: View {
    struct Palette {
        let text: Color
        let secondary: Color
        let divider: Color
        let field: Color

        static let light = Palette(text: Theme.text, secondary: Theme.secondaryText, divider: Theme.divider, field: Theme.softGrey)
        static let dark = Palette(text: Theme.panelText, secondary: Theme.panelSecondary, divider: Theme.panelHairline,
                                  field: Theme.panelCard)
    }

    let model: FavouritesModel
    let palette: Palette
    /// The bottom sheet scrolls its rows between a fixed title and 完成; the side panel scrolls as a whole.
    let scrolls: Bool
    let onDone: () -> Void

    @State private var editing = false
    @State private var newTitle = ""
    @State private var newPrivate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("选择收藏夹")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(palette.text)
                .frame(height: 30)
                .padding(.bottom, 6)
            if scrolls {
                ScrollView(showsIndicators: false) { rows }
            } else {
                rows
            }
            Button(action: onDone) {
                Text("完成")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Favourites.doneText)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Favourites.doneHeight)
                    .background(Theme.pink, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            newFolder
            switch model.phase {
            case .loading:
                ProgressView()
                    .tint(palette.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            case .failed:
                Button {
                    Task { await model.load() }
                } label: {
                    Text("加载失败，点击重试")
                        .font(Theme.Favourites.countFont)
                        .foregroundStyle(palette.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            case .loaded:
                ForEach(model.folders) { folder in
                    row(folder)
                }
            }
        }
    }

    private func row(_ folder: FavFolder) -> some View {
        let on = model.ticked.contains(folder.id)
        return Button {
            model.toggle(folder.id)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(folder.title)
                            .font(Theme.Favourites.titleFont)
                            .foregroundStyle(palette.text)
                            .lineLimit(1)
                        if folder.isPrivate {
                            Image(systemName: "lock")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.secondary)
                        }
                    }
                    Text("\(folder.count)个内容")
                        .font(Theme.Favourites.countFont)
                        .foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: Theme.Favourites.check))
                    .foregroundStyle(on ? Theme.pink : palette.secondary)
            }
            .frame(height: Theme.Favourites.rowHeight)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(palette.divider)
                    .frame(height: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(folder.isPrivate ? "\(folder.title)，私密" : folder.title)
        .accessibilityValue("\(folder.count)个内容")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var newFolder: some View {
        if editing {
            VStack(alignment: .leading, spacing: 10) {
                TextField("收藏夹名称", text: $newTitle)
                    .font(Theme.Favourites.titleFont)
                    .foregroundStyle(palette.text)
                    .submitLabel(.done)
                    .onSubmit(create)
                    .onChange(of: newTitle) { _, title in
                        if title.count > Theme.Favourites.maxTitle { newTitle = String(title.prefix(Theme.Favourites.maxTitle)) }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: Theme.Favourites.fieldHeight)
                    .background(palette.field, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
                HStack(spacing: 8) {
                    Text("私密")
                        .font(Theme.Favourites.titleFont)
                        .foregroundStyle(palette.text)
                    Toggle("私密", isOn: $newPrivate)
                        .labelsHidden()
                        .tint(Theme.pink)
                        .scaleEffect(0.8)
                    Spacer(minLength: 8)
                    Button("取消") {
                        editing = false
                        newTitle = ""
                        model.error = nil
                    }
                    .foregroundStyle(palette.secondary)
                    Button("创建", action: create)
                        .foregroundStyle(Theme.pink)
                        .disabled(model.creating || newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .font(Theme.Favourites.titleFont)
                .buttonStyle(.plain)
                if let error = model.error {
                    Text(error)
                        .font(Theme.Favourites.countFont)
                        .foregroundStyle(Theme.Page.forbidden)
                }
            }
            .padding(.vertical, 10)
        } else {
            Button {
                editing = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("新建收藏夹")
                }
                .font(Theme.Favourites.titleFont)
                .foregroundStyle(Theme.pink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func create() {
        let title = newTitle
        let isPrivate = newPrivate
        Task {
            if await model.create(title: title, isPrivate: isPrivate) {
                editing = false
                newTitle = ""
                newPrivate = false
            }
        }
    }
}

/// The portrait sheet: light like the page under it, over a dimmed screen whose tap closes it.
private struct LightSheet<Content: View>: View {
    let identifier: String
    let height: CGFloat
    let dismiss: () -> Void
    @ViewBuilder let content: (_ close: @escaping () -> Void) -> Content

    @State private var shown = false
    @State private var closing = false

    private static var motion: Animation { .smooth(duration: 0.25) }

    var body: some View {
        let bottom = PanelInsets.window.bottom
        let full = height + bottom
        ZStack(alignment: .bottom) {
            Theme.Favourites.dim
                .opacity(shown ? 1 : 0)
                .allowsHitTesting(false)
            TapCatcher(onTap: close)
            VStack(spacing: 0) {
                Capsule()
                    .fill(Theme.Page.grabber)
                    .frame(width: 30, height: 3.5)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture().onEnded { drag in
                        if drag.translation.height > 40 { close() }
                    })
                content(close)
                    .padding(.horizontal, Theme.Metrics.gutter + 4)
                    .padding(.bottom, max(bottom, 12))
            }
            .frame(height: full, alignment: .top)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: Theme.Page.sheetRadius, topTrailingRadius: Theme.Page.sheetRadius)
                    .fill(Theme.Page.background)
            }
            .hitTestable(height: full)
            .background(PanelProbe(identifier: identifier))
            .offset(y: shown ? 0 : full)
        }
        .onAppear {
            withAnimation(Self.motion) { shown = true }
        }
    }

    private func close() {
        guard !closing else { return }
        closing = true
        withAnimation(Self.motion) { shown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            dismiss()
        }
    }
}
