import AppKit
import SwiftUI

// MARK: - 多行输入（内部是 [String]）
//
// 表单里到处都是「一行一条」的输入：功能清单、约束、字段、操作、属性。
// 引擎吃的是 [String]，但用户需要一个能自由换行的编辑框，所以这里做一层双向转换。
//
// 用 @State + syncing 闸门而不是计算属性 Binding：TextEditor 绑到计算 Binding 时
// 光标位置容易在输入过程中被重置，实机上手感很差。
struct ProtoLinesEditor: View {
    var placeholder: String
    @Binding var lines: [String]
    var minHeight: CGFloat = 84

    @State private var text = ""
    @State private var syncing = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 12.5))
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
                    .font(.system(size: 12.5))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { text = lines.joined(separator: "\n") }
        .onChange(of: text) { _, value in
            guard !syncing else { return }
            syncing = true
            lines = value.isEmpty ? [] : value.components(separatedBy: "\n")
            syncing = false
        }
        .onChange(of: lines) { _, value in
            guard !syncing else { return }
            let joined = value.joined(separator: "\n")
            guard joined != text else { return }
            syncing = true
            text = joined
            syncing = false
        }
    }
}

// MARK: - 一行选项（标签 + 一堆 chip）

struct ProtoOptionRow<Content: View>: View {
    var title: String
    var labelWidth: CGFloat = 58
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)
                .padding(.top, 5)

            FlowRow(spacing: 6) { content }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 开关行

struct ProtoToggleRow: View {
    var title: String
    var hint: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5))
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }
}

// MARK: - 预设

struct ProtoPresetGrid: View {
    let presets: [ProtoPreset]
    var recentIDs: [String] = []
    var onApply: (ProtoPreset) -> Void

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(presets) { preset in
                Button {
                    onApply(preset)
                } label: {
                    card(preset)
                }
                .buttonStyle(.plain)
                .help(preset.summary)
            }
        }
    }

    private func card(_ preset: ProtoPreset) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: preset.kind.systemImage)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(preset.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if recentIDs.contains(preset.id) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(preset.summary)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}

// MARK: - 工具做了什么

struct ProtoFeedbackCard: View {
    let output: ProtoOutput

    var body: some View {
        ToolCard(title: "工具做了什么", systemImage: "wand.and.stars") {
            VStack(alignment: .leading, spacing: 12) {
                if !output.warnings.isEmpty {
                    group("先补上这几项", output.warnings, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                }
                if !output.filled.isEmpty {
                    group("自动补齐", output.filled, systemImage: "checkmark.circle.fill", tint: .green)
                }
                if !output.todo.isEmpty {
                    group("必须你自己定", output.todo, systemImage: "hand.point.right.fill", tint: .orange)
                }
                if !output.notes.isEmpty {
                    group("留意", output.notes, systemImage: "info.circle.fill", tint: .secondary)
                }
            }
        }
    }

    private func group(_ title: String, _ items: [String], systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(item)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - 输出面板

struct ProtoOutputPane: View {
    var title: String
    var text: String
    var placeholder: String
    var minHeight: CGFloat = 320
    /// 保存时的建议文件名，带扩展名
    var saveAs: String?
    var onNotify: ((String) -> Void)?

    var body: some View {
        TextPane(
            title: title,
            text: .constant(text),
            isEditable: false,
            placeholder: placeholder,
            minHeight: minHeight,
            buttons: buttons
        )
    }

    private var buttons: [PaneButton] {
        var items: [PaneButton] = []

        if let saveAs {
            items.append(PaneButton(systemImage: "square.and.arrow.down", help: "保存为文件") {
                if FilePicker.saveText(text, suggestedName: saveAs) != nil {
                    onNotify?("已保存到 \(saveAs)")
                }
            })
        }

        items.append(PaneButton(systemImage: "doc.on.doc", help: "复制全文", tint: .accentColor) {
            NSPasteboard.copyString(text)
            onNotify?("已复制，粘到 AI 对话框里就行")
        })

        return items
    }
}

// MARK: - 左右分栏外壳
//
// 四个面板都是「左边填、右边出结果」。窗口宽度够，分开比上下滚到底看结果舒服得多。
struct ProtoSplit<Left: View, Right: View>: View {
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    init(@ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self.left = left()
        self.right = right()
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) { left }
                    .padding(18)
            }
            .frame(width: 400)

            Divider()

            ScrollView {
                VStack(spacing: 14) { right }
                    .padding(18)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - 小标题

struct ProtoHint: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
