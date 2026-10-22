import AppKit
import SwiftUI

// MARK: - 文本面板

/// 面板右上角的小图标按钮
struct PaneButton: Identifiable {
    let id = UUID()
    var systemImage: String
    var help: String
    var tint: Color = .secondary
    var action: () -> Void
}

/// 多行文本输入 / 输出面板。
///
/// 可编辑时是 `TextEditor`；只读时退化成可选中的文本，方便直接划拉复制。
struct TextPane: View {
    var title: String
    @Binding var text: String
    var isEditable: Bool = true
    var placeholder: String = "在这里输入…"
    var minHeight: CGFloat = 170
    var buttons: [PaneButton] = []

    private var monoFont: Font { .system(size: 12.5, design: .monospaced) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            editor
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.4)

            Spacer(minLength: 8)

            if !text.isEmpty {
                Text("\(text.count) 字符")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            ForEach(buttons) { button in
                Button {
                    button.action()
                } label: {
                    Image(systemName: button.systemImage)
                        .foregroundStyle(button.tint)
                }
                .buttonStyle(.borderless)
                .help(button.help)
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        if isEditable {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(monoFont)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: minHeight)
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10))
                    )
                if text.isEmpty {
                    Text(placeholder)
                        .font(monoFont)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
        } else {
            ScrollView {
                Text(text.isEmpty ? placeholder : text)
                    .font(monoFont)
                    .foregroundStyle(text.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10))
            )
        }
    }
}

// MARK: - 错误条

/// 转换失败的提示条（红底 + 说明），比 Toast 更适合需要常驻显示的错误
struct ErrorBanner: View {
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.28))
        )
    }
}

// MARK: - 小标签

/// 说明型小标签（"弱算法""单向不可逆"这类提示）
struct NoticeTag: View {
    var text: String
    var systemImage: String
    var tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

// MARK: - 文件选择

enum FilePicker {
    /// 选一个文件（任意类型），哈希工具用
    static func pick(title: String = "选择文件") -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = title
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// 保存纯文本（编码结果导出用）
    static func saveText(_ text: String, suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.title = "保存"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            NSSound.beep()
            return nil
        }
    }
}
