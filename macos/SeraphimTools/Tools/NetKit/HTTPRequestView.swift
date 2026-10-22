import AppKit
import SwiftUI

/// HTTP 请求器：发一次请求，看状态、头、体，还有每段耗时。
struct HTTPRequestView: View {
    @AppStorage("httpMethod") private var method = "GET"
    @AppStorage("httpURL") private var url = ""
    @AppStorage("httpBodyMode") private var bodyMode: HTTPBodyMode = .none

    @State private var headers: [NetPair] = [NetPair(name: "Accept", value: "application/json")]
    @State private var rawBody = ""
    @State private var formFields: [NetPair] = []
    @State private var fileFields: [NetPair] = []
    @State private var timeout: Double = 30
    @State private var followRedirects = true
    @State private var allowInsecureTLS = false

    @State private var exchange: HTTPExchange?
    @State private var history: [HTTPExchange] = []
    @State private var isSending = false
    @State private var sendTask: Task<Void, Never>?
    @State private var prettyBody = true
    @State private var toast: String?

    private static let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    private var spec: HTTPRequestSpec {
        HTTPRequestSpec(
            method: method,
            url: url,
            headers: headers,
            bodyMode: bodyMode,
            rawBody: rawBody,
            formFields: formFields,
            fileFields: fileFields,
            timeout: timeout,
            followRedirects: followRedirects,
            allowInsecureTLS: allowInsecureTLS
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                requestCard
                bodyCard
                optionsCard
                if let exchange {
                    ResponseCard(
                        exchange: exchange,
                        prettyBody: $prettyBody,
                        curl: curlCommand,
                        onCopy: { toast = "已复制" }
                    )
                }
                if !history.isEmpty {
                    historyCard
                }
            }
            .padding(20)
        }
        .toast($toast)
        .onDisappear { sendTask?.cancel() }
    }

    private var curlCommand: String {
        CurlEngine.command(for: CurlEngine.request(from: spec), style: .multiLine)
    }

    // MARK: 请求行

    private var requestCard: some View {
        ToolCard(title: "请求", systemImage: "paperplane") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Picker("方法", selection: $method) {
                        ForEach(Self.methods, id: \.self) { item in
                            Text(item).tag(item)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 108)

                    TextField("https://api.example.com/v1/items", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                        .onSubmit { send() }

                    if isSending {
                        Button(role: .destructive) {
                            sendTask?.cancel()
                            isSending = false
                        } label: {
                            Label("取消", systemImage: "stop.fill")
                        }
                    } else {
                        Button {
                            send()
                        } label: {
                            Label("发送", systemImage: "arrow.up.circle.fill")
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }

                NetPairEditor(
                    title: "请求头",
                    systemImage: "list.bullet.rectangle",
                    namePlaceholder: "Header",
                    valuePlaceholder: "值",
                    pairs: $headers,
                    addTitle: "加一条"
                )

                if url.isEmpty {
                    Text("提示：不写协议也认，默认按 http:// 走；要打本地自签证书的 https，下面勾「信任自签证书」。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: 请求体

    private var bodyCard: some View {
        ToolCard(title: "请求体", systemImage: "doc.text") {
            VStack(alignment: .leading, spacing: 12) {
                NetChipPicker(options: HTTPBodyMode.allCases, selection: $bodyMode) { $0.title }

                switch bodyMode {
                case .none:
                    Text("不带请求体")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)

                case .json, .raw:
                    TextPane(
                        title: bodyMode == .json ? "JSON" : "原始文本",
                        text: $rawBody,
                        placeholder: bodyMode == .json ? "{\n  \"key\": \"value\"\n}" : "随便写点什么",
                        minHeight: 120
                    )

                case .form:
                    NetPairEditor(
                        title: "表单字段",
                        systemImage: "square.grid.2x2",
                        namePlaceholder: "字段名",
                        valuePlaceholder: "值",
                        pairs: $formFields,
                        addTitle: "加字段"
                    )

                case .multipart:
                    VStack(alignment: .leading, spacing: 14) {
                        NetPairEditor(
                            title: "文本字段",
                            systemImage: "text.cursor",
                            namePlaceholder: "字段名",
                            valuePlaceholder: "值",
                            pairs: $formFields,
                            addTitle: "加字段"
                        )
                        NetPairEditor(
                            title: "文件字段",
                            systemImage: "paperclip",
                            namePlaceholder: "字段名（如 file）",
                            valuePlaceholder: "文件路径，如 ~/Desktop/a.png",
                            pairs: $fileFields,
                            addTitle: "加文件"
                        )
                        Text("文件按路径读取，Content-Type 按扩展名猜；多部分体的边界会自动生成。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: 选项

    private var optionsCard: some View {
        ToolCard(title: "选项", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("超时")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(timeout)) 秒")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        Slider(value: $timeout, in: 1...120, step: 1)
                            .controlSize(.small)
                            .frame(width: 200)
                    }

                    Toggle("跟随重定向", isOn: $followRedirects)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    Toggle("信任自签证书", isOn: $allowInsecureTLS)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    Spacer(minLength: 0)
                }

                Text("关掉「跟随重定向」时，3xx 响应会直接显示出来，方便看 Location 头。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 历史

    private var historyCard: some View {
        ToolCard(title: "本次会话历史", systemImage: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(history) { item in
                    Button {
                        method = item.method
                        url = item.url
                        toast = "已回填到请求行"
                    } label: {
                        HStack(spacing: 10) {
                            NetStatusPill(
                                text: "\(item.statusCode)",
                                tint: statusTint(item),
                                systemImage: item.failure == nil ? "circle.fill" : "exclamationmark.triangle.fill"
                            )
                            Text(item.method)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .frame(width: 54, alignment: .leading)
                            Text(item.url)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if let total = item.timings.total {
                                Text(String(format: "%.0f ms", total))
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func statusTint(_ exchange: HTTPExchange) -> Color {
        if exchange.failure != nil { return .red }
        switch exchange.statusCode {
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        default: return .red
        }
    }

    // MARK: 发送

    private func send() {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            toast = "先填请求地址"
            NSSound.beep()
            return
        }

        sendTask?.cancel()
        isSending = true
        let currentSpec = spec

        sendTask = Task {
            let result = await HTTPEngine.send(currentSpec)
            if Task.isCancelled { return }
            exchange = result
            history.insert(result, at: 0)
            if history.count > 12 { history.removeLast(history.count - 12) }
            isSending = false
        }
    }
}

// MARK: - 响应卡片

private struct ResponseCard: View {
    let exchange: HTTPExchange
    @Binding var prettyBody: Bool
    let curl: String
    let onCopy: () -> Void

    private var displayBody: String {
        guard prettyBody, exchange.isJSON else { return exchange.bodyText }
        return JSONBeautifier.pretty(exchange.bodyText) ?? exchange.bodyText
    }

    private var headerText: String {
        exchange.responseHeaders.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
    }

    var body: some View {
        ToolCard(title: "响应", systemImage: "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 14) {
                statusRow
                if let failure = exchange.failure {
                    ErrorBanner(message: failure)
                }
                timingRow
                if !exchange.redirects.isEmpty {
                    redirectList
                }
                TextPane(
                    title: "响应头",
                    text: .constant(headerText),
                    isEditable: false,
                    placeholder: "没有响应头",
                    minHeight: 90,
                    buttons: [PaneButton(systemImage: "doc.on.doc", help: "复制响应头", action: {
                        NSPasteboard.copyString(headerText)
                        onCopy()
                    })]
                )
                TextPane(
                    title: "响应体",
                    text: .constant(displayBody),
                    isEditable: false,
                    placeholder: exchange.failure == nil ? "（空）" : "请求没发出去",
                    minHeight: 220,
                    buttons: [
                        PaneButton(
                            systemImage: prettyBody ? "text.alignleft" : "curlybraces",
                            help: prettyBody ? "显示原始内容" : "美化 JSON",
                            action: { prettyBody.toggle() }
                        ),
                        PaneButton(systemImage: "doc.on.doc", help: "复制响应体", action: {
                            NSPasteboard.copyString(exchange.bodyText)
                            onCopy()
                        }),
                        PaneButton(systemImage: "square.and.arrow.down", help: "保存响应体", action: {
                            _ = FilePicker.saveText(exchange.bodyText, suggestedName: "response.txt")
                        }),
                    ]
                )
            }
        }
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                NetStatusPill(
                    text: exchange.failure == nil ? "\(exchange.statusCode) \(exchange.statusText)" : "未完成",
                    tint: tint,
                    systemImage: exchange.failure == nil ? "circle.fill" : "exclamationmark.triangle.fill"
                )
                if exchange.failure == nil {
                    Text(NetErrorText.statusNote(exchange.statusCode))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                NetStatusPill(text: ByteCountText.format(exchange.bodyBytes), tint: .secondary)
                if !exchange.contentType.isEmpty {
                    NetStatusPill(text: shortContentType, tint: .secondary)
                }
                Spacer(minLength: 0)
                Button {
                    NSPasteboard.copyString(curl)
                    onCopy()
                } label: {
                    Label("复制为 cURL", systemImage: "terminal")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
                .help("把这次请求的命令行版本复制走")
            }

            NetFieldRow(label: "最终地址", value: exchange.finalURL)
            if exchange.finalURL != exchange.url {
                NetFieldRow(label: "原始地址", value: exchange.url)
            }
        }
    }

    private var tint: Color {
        if exchange.failure != nil { return .red }
        switch exchange.statusCode {
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        default: return .red
        }
    }

    private var shortContentType: String {
        exchange.contentType.split(separator: ";").first.map(String.init) ?? exchange.contentType
    }

    private var timingRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            NetSectionLabel(
                title: "耗时分解",
                systemImage: "stopwatch",
                trailing: exchange.timings.reusedConnection ? "复用了已有连接（没有 DNS / TCP 阶段）" : nil
            )
            FlowRow(spacing: 8) {
                NetStatTile(title: "DNS", value: text(exchange.timings.dns), tint: .secondary)
                NetStatTile(title: "TCP 连接", value: text(exchange.timings.connect), tint: .secondary)
                NetStatTile(title: "TLS 握手", value: text(exchange.timings.tls), tint: .secondary)
                NetStatTile(title: "发送请求", value: text(exchange.timings.send), tint: .secondary)
                NetStatTile(title: "等待响应", value: text(exchange.timings.waiting), tint: .orange)
                NetStatTile(title: "接收内容", value: text(exchange.timings.download), tint: .secondary)
                NetStatTile(title: "总计", value: text(exchange.timings.total), tint: .accentColor)
            }
        }
    }

    private func text(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f ms", value)
    }

    private var redirectList: some View {
        VStack(alignment: .leading, spacing: 6) {
            NetSectionLabel(title: "重定向链", systemImage: "arrow.triangle.turn.up.right.diamond", trailing: "\(exchange.redirects.count) 跳")
            ForEach(Array(exchange.redirects.enumerated()), id: \.offset) { index, hop in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14)
                    Text(hop)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

enum ByteCountText {
    static func format(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kilobytes = Double(bytes) / 1024
        if kilobytes < 1024 { return String(format: "%.1f KB", kilobytes) }
        return String(format: "%.2f MB", kilobytes / 1024)
    }
}
