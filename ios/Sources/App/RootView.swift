import SwiftUI
import Ripper

struct RootView: View {
    var body: some View {
        NavigationStack {
            List {
                Text("版本 \(AppInfo.version)")
                Text("引擎节点：\(NodeCatalog.overseas.count) 个海外节点")
            }
            .navigationTitle(AppInfo.displayName)
        }
    }
}
