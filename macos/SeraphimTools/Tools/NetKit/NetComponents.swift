import AppKit
import SwiftUI

// MARK: - 结果行

/// 「标签 — 值」一行，结果卡片里到处在用
struct NetFieldRow: View {
    let label: String
    let value: String
    var mono = true
    var highlight = false
    var tint: Color = .primary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Text(value)
                .font(.system(size: 12, design: mono ? .monospaced : .default))
                .foregroundStyle(highlight ? Color.accentColor : tint)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

/// 耗时分解 / 统计用的方块
struct NetStatTile: View {
    let title: String
    let value: String
    var tint: Color = .secondary
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(tint)
            if let hint {
                Text(hint)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.quaternary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(minWidth: 86, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }
}

/// 状态胶囊
struct NetStatusPill: View {
    let text: String
    var tint: Color = .secondary
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9.5))
            }
            Text(text).font(.system(size: 10.5, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.15), in: Capsule())
        .foregroundStyle(tint)
    }
}

/// 卡片里的小标题
struct NetSectionLabel: View {
    let title: String
    var systemImage: String?
    var trailing: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 输入行

/// 一行「标签 + 输入框」，可选右侧附加控件
struct NetLabeledField<Accessory: View>: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String
    var width: CGFloat = 260
    var mono = true
    var accessory: Accessory

    init(
        label: String,
        placeholder: String = "",
        text: Binding<String>,
        width: CGFloat = 260,
        mono: Bool = true,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.width = width
        self.mono = mono
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)

            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5, design: mono ? .monospaced : .default))
                .frame(maxWidth: width)

            accessory
            Spacer(minLength: 0)
        }
    }
}

extension NetLabeledField where Accessory == EmptyView {
    init(label: String, placeholder: String = "", text: Binding<String>, width: CGFloat = 260, mono: Bool = true) {
        self.init(label: label, placeholder: placeholder, text: text, width: width, mono: mono) {
            EmptyView()
        }
    }
}

// MARK: - 键值对编辑器

/// 请求头 / 表单字段 / curl 参数共用的编辑器
struct NetPairEditor: View {
    var title: String
    var systemImage: String = "list.bullet"
    var namePlaceholder: String = "名称"
    var valuePlaceholder: String = "值"
    @Binding var pairs: [NetPair]
    var addTitle: String = "添加"
    var showsEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                NetSectionLabel(title: title, systemImage: systemImage, trailing: pairs.isEmpty ? nil : "\(pairs.count) 条")
                Button {
                    pairs.append(NetPair())
                } label: {
                    Label(addTitle, systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }

            if pairs.isEmpty {
                Text("还没加内容")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach($pairs) { $pair in
                    pairRow($pair)
                }
            }
        }
    }

    private func pairRow(_ pair: Binding<NetPair>) -> some View {
        HStack(spacing: 8) {
            if showsEnabled {
                Toggle("", isOn: pair.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .help("临时停用这一条")
            }

            TextField(namePlaceholder, text: pair.name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 168)

            TextField(valuePlaceholder, text: pair.value)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            Button {
                let identifier = pair.wrappedValue.id
                pairs.removeAll { $0.id == identifier }
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("删除")
        }
    }
}

// MARK: - 可折行的选项 chip

/// 长标签（如「表单 (--data-urlencode)」）放分段控件会把整页撑宽，
/// 用 chip 行替代：窗口窄了自动折行，不会挤压布局。
struct NetChipPicker<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    var label: (Option) -> String

    var body: some View {
        FlowRow(spacing: 8) {
            ForEach(options, id: \.self) { option in
                ChipButton(title: label(option), isSelected: option == selection) {
                    selection = option
                }
            }
        }
    }
}

// MARK: - 小工具

enum NetClipboard {
    static func copy(_ text: String, toast: inout String?, message: String = "已复制") {
        NSPasteboard.copyString(text)
        toast = message
    }
}
