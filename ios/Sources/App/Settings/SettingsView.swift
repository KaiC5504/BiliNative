import SwiftUI
import DevLog

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var pendingClear: ClearAction?
    #if DEV_TOOLS
    @State private var discovery = LogServerDiscovery()
    @State private var networkState = ""
    @State private var exportURL: URL?
    @State private var confirmCrash = false
    #endif

    private enum ClearAction: String {
        case codecMemory, recents, logs

        var title: String {
            switch self {
            case .codecMemory: return "重置编码记忆？"
            case .recents: return "清除最近观看？"
            case .logs: return "清除日志？"
            }
        }

        var message: String {
            switch self {
            case .codecMemory: return "本机播放失败过的编码会重新参与尝试。"
            case .recents: return "首页的最近观看列表会被清空。"
            case .logs: return "手机上保存的调试日志会被删除，已发送到电脑的不受影响。"
            }
        }

        var confirm: String {
            switch self {
            case .codecMemory: return "重置"
            case .recents, .logs: return "清除"
            }
        }
    }

    var body: some View {
        @Bindable var settings = env.settings
        NavigationStack {
            Form {
                Section("加速") {
                    Picker("CDN 节点", selection: $settings.nodeChoice) {
                        ForEach(AppSettings.NodeChoice.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("BTR 加速（默认）", isOn: $settings.btrEnabled)
                }
                Section("数据") {
                    Button("重置编码记忆") { pendingClear = .codecMemory }
                    Button("清除最近观看", role: .destructive) { pendingClear = .recents }
                        .disabled(env.recents.items.isEmpty)
                    Button("清除日志", role: .destructive) { pendingClear = .logs }
                }
                #if DEV_TOOLS
                Section {
                    Toggle("发送日志到电脑", isOn: $settings.logServerEnabled)
                    if settings.logServerEnabled {
                        ForEach(discovery.services, id: \.self) { name in
                            Button {
                                settings.logServerService = name
                            } label: {
                                HStack {
                                    Text(name)
                                    Spacer()
                                    if settings.logServerService == name { Image(systemName: "checkmark") }
                                }
                            }
                        }
                        TextField("或手动输入 IP:端口", text: $settings.logServerManual)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit {
                                settings.logServerService = ""
                                DevLogSetup.apply(settings)
                            }
                        Text(networkState).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let exportURL {
                        ShareLink("导出日志文件", item: exportURL)
                    } else {
                        Button("准备导出日志") { exportURL = DevLogSetup.exportFile() }
                    }
                    Button("测试崩溃", role: .destructive) { confirmCrash = true }
                        .confirmationDialog("让应用立即崩溃？", isPresented: $confirmCrash, titleVisibility: .visible) {
                            Button("崩溃", role: .destructive) {
                                Logger.shared.warn(.ui, "test crash")
                                fatalError("开发者测试崩溃")
                            }
                        } message: {
                            Text("重新打开后，崩溃报告会作为 crash 事件发送到电脑。")
                        }
                } header: {
                    Text("开发者")
                } footer: {
                    Text("在电脑上运行 uv run tools/logserver.py，手机和电脑连同一个 Wi-Fi。")
                }
                #endif
                Section {
                    LabeledContent("版本", value: AppInfo.version)
                    Text("下载加速移植自 Bilibili 线程撕裂者（BTR），MIT 许可。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .confirmationDialog(Text(pendingClear?.title ?? ""),
                                isPresented: Binding(get: { pendingClear != nil }, set: { if !$0 { pendingClear = nil } }),
                                titleVisibility: .visible, presenting: pendingClear) { action in
                Button(action.confirm, role: .destructive) { perform(action) }
            } message: { action in
                Text(action.message)
            }
            #if DEV_TOOLS
            // Browsing triggers the Local Network prompt, so it runs only while sending is switched on.
            .onAppear { if settings.logServerEnabled { discovery.start() } }
            .onDisappear {
                discovery.stop()
                DevLogSetup.apply(settings)
            }
            .onChange(of: settings.logServerEnabled) { _, enabled in
                if enabled { discovery.start() } else { discovery.stop() }
                DevLogSetup.apply(settings)
            }
            .onChange(of: settings.logServerService) { DevLogSetup.apply(settings) }
            // Typing an address means using it: a selected service would otherwise win over it silently.
            .onChange(of: settings.logServerManual) { settings.logServerService = "" }
            .task {
                while !Task.isCancelled {
                    networkState = DevLogSetup.networkState(settings)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            #endif
        }
    }

    private func perform(_ action: ClearAction) {
        switch action {
        case .codecMemory:
            env.codecMemory.reset()
        case .recents:
            env.recents.clear()
        case .logs:
            DevLogSetup.clearFiles()
            #if DEV_TOOLS
            exportURL = nil
            #endif
        }
        Logger.shared.info(.ui, "settings clear", ["what": .init(action.rawValue)])
    }
}
