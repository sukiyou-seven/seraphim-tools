import SwiftUI
import AppKit

/// 统一的卡片容器
struct ToolCard<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label(title, systemImage: systemImage ?? "circle.dashed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.4)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

/// 透明背景预览用的棋盘格
struct Checkerboard: View {
    var square: CGFloat = 10
    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / square))
            let rows = Int(ceil(size.height / square))
            for row in 0..<max(rows, 0) {
                for col in 0..<max(cols, 0) {
                    let isDark = (row + col).isMultiple(of: 2)
                    let rect = CGRect(
                        x: CGFloat(col) * square,
                        y: CGFloat(row) * square,
                        width: square,
                        height: square
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isDark ? Color.gray.opacity(0.20) : Color.gray.opacity(0.08))
                    )
                }
            }
        }
    }
}

/// 点击后短暂显示对勾的复制按钮
struct CopyIconButton: View {
    let text: String
    var help: String = "复制"

    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.copyString(text)
            withAnimation(.easeOut(duration: 0.15)) { copied = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation(.easeIn(duration: 0.2)) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .foregroundStyle(copied ? Color.green : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
        .disabled(text.isEmpty)
    }
}

/// 简易自动换行的横向布局（按钮组、标签组用）
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]
        var rowHeights: [CGFloat] = [0]
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let current = rows[rows.count - 1]
            if current > 0, current + spacing + size.width > maxWidth {
                rows.append(size.width)
                rowHeights.append(size.height)
            } else {
                rows[rows.count - 1] = current == 0 ? size.width : current + spacing + size.width
                rowHeights[rowHeights.count - 1] = max(rowHeights[rowHeights.count - 1], size.height)
            }
        }
        let width = rows.max() ?? 0
        let height = rowHeights.reduce(0, +) + spacing * CGFloat(max(0, rowHeights.count - 1))
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 胶囊选择按钮（格式选择、比例选择这类场景）
struct ChipButton: View {
    let title: String
    var isSelected: Bool = false
    var isEnabled: Bool = true
    var minWidth: CGFloat = 0
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .frame(minWidth: minWidth)
                .background(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.07),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.white : (isEnabled ? Color.primary : Color.secondary))
                .overlay(
                    Capsule().strokeBorder(Color.primary.opacity(isSelected ? 0 : 0.10))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

/// 底部短暂提示条
struct ToastOverlay: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                    .shadow(radius: 8, y: 2)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        withAnimation(.easeInOut(duration: 0.2)) { self.message = nil }
                    }
            }
        }
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastOverlay(message: message))
    }
}

enum PasteboardWriter {
    static func copyImage(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}

extension NSPasteboard {
    static func copyString(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
