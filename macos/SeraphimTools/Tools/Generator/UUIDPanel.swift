import AppKit
import SwiftUI

/// UUID：v1/v3/v4/v5/v6/v7 生成与解析。
///
/// 解析这块做得比较细——拿到一个来路不明的 UUID，能一眼看出它是哪个版本、
/// 什么时候生成的、里面塞的是 MAC 还是随机数。
struct UUIDPanel: View {
    @AppStorage("uuidVersion") private var version: UUIDVersion = .v4
    @AppStorage("uuidCount") private var count = 5
    @AppStorage("uuidNamespace") private var namespace: UUIDNamespaceKind = .dns
    @AppStorage("uuidName") private var name = "example.com"
    @AppStorage("uuidRealNode") private var useRealNode = false
    @AppStorage("uuidParseText") private var parseText = ""

    @State private var generated: [String] = []
    @State private var parsed: UUIDParseResult?
    @State private var parseError: String?
    @State private var toast: String?
    @State private var didAutoRun = false

    private let counts = [1, 5, 10, 20, 50]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                generateCard
                parseCard
            }
            .padding(20)
        }
        .toast($toast)
        .onAppear {
            guard !didAutoRun else { return }
            didAutoRun = true
            generate()
            runParse()
        }
    }

    // MARK: 生成

    private var generateCard: some View {
        ToolCard(title: "生成", systemImage: "wand.and.stars") {
            VStack(alignment: .leading, spacing: 12) {
                FlowRow(spacing: 6) {
                    ForEach(UUIDVersion.allCases) { item in
                        ChipButton(title: item.title, isSelected: item == version) {
                            version = item
                            generate()
                        }
                    }
                }

                Text(version.note)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if version.isNamed {
                    namedControls
                } else if version == .v1 || version == .v6 {
                    nodeControls
                }

                if !version.isNamed {
                    HStack(spacing: 8) {
                        Text("数量")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        FlowRow(spacing: 6) {
                            ForEach(counts, id: \.self) { value in
                                ChipButton(title: "\(value)", isSelected: value == count) {
                                    count = value
                                    generate()
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        generate()
                    } label: {
                        Label("生成", systemImage: "arrow.clockwise").font(.system(size: 12))
                    }
                    .controlSize(.small)

                    Button {
                        guard !generated.isEmpty else { return }
                        NSPasteboard.copyString(generated.joined(separator: "\n"))
                        toast = "已复制 \(generated.count) 条"
                    } label: {
                        Label("复制全部", systemImage: "doc.on.doc").font(.system(size: 12))
                    }
                    .controlSize(.small)
                    .disabled(generated.isEmpty)

                    Spacer(minLength: 0)

                    if version.isNamed {
                        NoticeTag(text: "确定性：同名同结果", systemImage: "equal.circle", tint: .blue)
                    } else if version == .v7 {
                        NoticeTag(text: "字符串排序 = 时间排序", systemImage: "arrow.up.arrow.down", tint: .green)
                    }
                }

                valueList
            }
        }
    }

    private var namedControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("命名空间")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                FlowRow(spacing: 6) {
                    ForEach(UUIDNamespaceKind.allCases) { item in
                        ChipButton(title: item.title, isSelected: item == namespace) {
                            namespace = item
                            generate()
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text("名字")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                TextField("要散列的名字，多个用逗号分隔", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, design: .monospaced))
                    .frame(maxWidth: 420)
                    .onSubmit { generate() }
                Button("生成") { generate() }
                    .controlSize(.small)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text(namespace.uuid.uuidString.lowercased())
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                Text(namespace.note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
        }
    }

    private var nodeControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("用本机网卡 MAC 当节点", isOn: $useRealNode)
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))
                .onChange(of: useRealNode) { _, _ in
                    UUIDV1Clock.shared.reseed()
                    generate()
                }

            Text(useRealNode
                 ? "节点 = 本机 MAC（\(UUIDEngine.localMACAddress() ?? "没读到，将退回随机节点")），会用真实网卡地址，能反查到设备"
                 : "节点 = 随机生成（多播位置 1，标明不是真网卡），不泄露设备信息，推荐这样用")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var valueList: some View {
        Group {
            if generated.isEmpty {
                Text("还没有生成内容")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(generated.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 12) {
                            Text(item)
                                .font(.system(size: 12.5, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Button {
                                parseText = item
                                runParse()
                            } label: {
                                Text("解析").font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                            CopyIconButton(text: item)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        if index < generated.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.025))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07))
                )
            }
        }
    }

    // MARK: 解析

    private var parseCard: some View {
        ToolCard(title: "解析", systemImage: "magnifyingglass") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField("粘贴一个 UUID（带不带连字符、大小写、{}、urn:uuid: 都认）", text: $parseText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                        .frame(maxWidth: 460)
                        .onSubmit { runParse() }

                    Button("解析") { runParse() }
                        .controlSize(.small)

                    Button {
                        if let first = generated.first {
                            parseText = first
                            runParse()
                        }
                    } label: {
                        Text("用上面第一个").font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                    .disabled(generated.isEmpty)

                    Spacer(minLength: 0)
                }

                if let parseError {
                    ErrorBanner(message: parseError)
                }

                if let parsed {
                    parseResult(parsed)
                } else if parseError == nil {
                    Text("解析会告诉你版本、变体、时间和节点来源。v3/v5 是散列出来的，反推不出原始名字。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func parseResult(_ result: UUIDParseResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                NoticeTag(text: result.versionTitle, systemImage: "number", tint: .accentColor)
                NoticeTag(text: result.versionNote, systemImage: "info.circle", tint: .secondary)
                NoticeTag(text: result.variant.title,
                          systemImage: result.variant.isStandard ? "checkmark.seal" : "exclamationmark.triangle",
                          tint: result.variant.isStandard ? .green : .orange)
                Spacer(minLength: 0)
            }

            if let timestamp = result.timestamp {
                HStack(spacing: 14) {
                    summaryItem("生成时间", Self.dateFormatter.string(from: timestamp))
                    summaryItem("距今", relative(timestamp))
                    if let sequence = result.clockSequence {
                        summaryItem("时钟序列", "\(sequence)")
                    }
                    Spacer(minLength: 0)
                }
                if let detail = result.timestampDetail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let node = result.node, let detail = result.nodeDetail {
                HStack(spacing: 8) {
                    Text("节点")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(width: 42, alignment: .leading)
                    Text(node)
                        .font(.system(size: 11.5, design: .monospaced))
                        .textSelection(.enabled)
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }

            fieldTable(result.fields)

            VStack(alignment: .leading, spacing: 6) {
                formatRow("标准", result.canonical)
                formatRow("紧凑（32 位）", result.compact)
                formatRow("URN", result.urn)
            }

            if !result.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(result.warnings, id: \.self) { note in
                        Text("· \(note)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private func fieldTable(_ fields: [UUIDField]) -> some View {
        VStack(spacing: 6) {
            ForEach(fields) { field in
                HStack(spacing: 10) {
                    Text(field.name)
                        .font(.system(size: 11.5, design: .monospaced))
                        .frame(width: 118, alignment: .leading)
                    Text(field.bits)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(width: 46, alignment: .leading)
                    Text(field.hex)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(minWidth: 74, alignment: .leading)
                    Text(field.meaning)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )
            }
        }
    }

    private func formatRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            CopyIconButton(text: value)
        }
    }

    private func summaryItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }

    private func relative(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        let future = seconds < 0
        let value = abs(seconds)
        let text: String
        switch value {
        case ..<60: text = String(format: "%.0f 秒", value)
        case ..<3600: text = String(format: "%.1f 分钟", value / 60)
        case ..<86400: text = String(format: "%.1f 小时", value / 3600)
        case ..<2_592_000: text = String(format: "%.1f 天", value / 86400)
        default: text = String(format: "%.1f 年", value / 31_557_600)
        }
        return future ? "还有 \(text)" : "\(text)前"
    }

    // MARK: 动作

    private func generate() {
        if version.isNamed {
            // 名字散列是确定性的：同一个名字永远同一个结果，所以这里按名字逐条算，
            // 多个名字用逗号分开
            let names = name
                .split(whereSeparator: { $0 == "," || $0 == "\n" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let targets = names.isEmpty ? [""] : names
            generated = targets.map {
                UUIDEngine.generateNamed(version: version, namespace: namespace.uuid, name: $0)
            }
        } else {
            generated = UUIDEngine.generate(version: version, count: max(1, count), useRealNode: useRealNode)
        }
    }

    private func runParse() {
        let text = parseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            parsed = nil
            parseError = nil
            return
        }
        do {
            parsed = try UUIDEngine.parse(text)
            parseError = nil
        } catch {
            parsed = nil
            parseError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}
