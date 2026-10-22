import SwiftUI

struct RootView: View {
    /// 记住上次打开的工具，下次启动直接回到那儿
    @AppStorage("selectedToolID") private var storedToolID: String = ToolCatalog.all.first?.id ?? ""
    @ObservedObject private var appState = AppState.shared

    private var selection: Binding<String?> {
        Binding(
            get: { storedToolID.isEmpty ? nil : storedToolID },
            set: { storedToolID = $0 ?? "" }
        )
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: selection)
                .navigationSplitViewColumnWidth(min: 216, ideal: 236, max: 320)
        } detail: {
            if let tool = ToolCatalog.tool(id: storedToolID) {
                ToolDetailView(tool: tool)
            } else {
                EmptyDetailView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        // 有图片从外部送进来时，自动切到图像工具
        .onChange(of: appState.pendingImageURL) { _, newValue in
            if newValue != nil {
                storedToolID = "image"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusImageTool)) { _ in
            storedToolID = "image"
        }
    }
}

private struct SidebarView: View {
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text("工具箱")
                        .font(.title2.bold())
                    Text("\(ToolCatalog.all.count) 个工具")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            .listRowSeparator(.hidden)

            ForEach(ToolCategory.allCases) { category in
                let tools = ToolCatalog.tools(in: category)
                if !tools.isEmpty {
                    Section(category.rawValue) {
                        ForEach(tools) { tool in
                            SidebarRow(tool: tool)
                                .tag(tool.id)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SidebarRow: View {
    let tool: ToolItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tool.tint)
                .frame(width: 24, height: 24)
                .background(tool.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(tool.title)
                    .font(.system(size: 13, weight: .medium))
                Text(tool.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text("左边挑一个工具")
                .font(.title3)
            Text("工具箱里还空着的话，去 ToolCatalog 加一行就有了。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ToolDetailView: View {
    let tool: ToolItem

    var body: some View {
        tool.makeView()
            .navigationTitle(tool.title)
            .navigationSubtitle(tool.summary)
    }
}
