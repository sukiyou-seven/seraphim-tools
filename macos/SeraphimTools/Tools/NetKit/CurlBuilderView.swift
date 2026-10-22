import AppKit
import SwiftUI

/// cURL 工具：表单拼命令，或者把命令拆回表单。
struct CurlBuilderView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case build
        case parse

        var id: String { rawValue }

        var title: String {
            switch self {
            case .build: return "表单 → 命令"
            case .parse: return "命令 → 表单"
            }
        }
    }

    @AppStorage("netCurlMode") private var mode: Mode = .build
    @AppStorage("curlURL") private var storedURL = ""

    @State private var request = CurlRequest(url: "https://api.example.com/v1/items", method: "POST")
    @State private var style: CurlStyle = .multiLine
    @State private var commandInput = ""
    @State private var warnings: [String] = []
    @State private var unknownFlags: [String] = []
    @State private var didLoadStoredURL = false
    @State private var toast: String?

    private let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    private var command: String {
        CurlEngine.command(for: request, style: style)
    }

    private var methodOptions: [String] {
        methods.contains(request.method) ? methods : [request.method] + methods
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    switch mode {
                    case .build:
                        targetCard
                        headerCard
                        bodyCard
                        authCard
                        flagsCard
                        outputCard
                    case .parse:
                        parseCard
                        if !warnings.isEmpty || !unknownFlags.isEmpty {
                            warningCard
                        }
                    }
                }
                .padding(20)
            }
        }
        .toast($toast)
        .onAppear {
            guard !didLoadStoredURL, !storedURL.isEmpty else { return }
            didLoadStoredURL = true
            request.url = storedURL
        }
        .onChange(of: request.url) { _, newValue in
            storedURL = newValue
        }
    }

    // MARK: 目标

    private var targetCard: some View {
        ToolCard(title: "目标", systemImage: "link") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Picker("方法", selection: $request.method) {
                        ForEach(methodOptions, id: \.self) { item in
                            Text(item).tag(item)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 108)

                    TextField("https://api.example.com/v1/items", text: $request.url)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                }

                HStack(spacing: 8) {
                    Text("生成风格")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("风格", selection: $style) {
                        ForEach(CurlStyle.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: 请求头

    private var headerCard: some View {
        ToolCard(title: "请求头", systemImage: "list.bullet.rectangle") {
            NetPairEditor(
                title: "Header",
                systemImage: "text.alignleft",
                namePlaceholder: "Content-Type",
                valuePlaceholder: "application/json",
                pairs: $request.headers,
                addTitle: "加一条"
            )
        }
    }

    // MARK: 请求体

    private var bodyCard: some View {
        ToolCard(title: "请求体", systemImage: "doc.text") {
            VStack(alignment: .leading, spacing: 12) {
                NetChipPicker(options: CurlBodyMode.allCases, selection: $request.bodyMode) { $0.title }

                switch request.bodyMode {
                case .none:
                    Text("不带请求体")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)

                case .json, .raw:
                    TextPane(
                        title: request.bodyMode == .json ? "JSON 内容" : "原始内容",
                        text: $request.rawBody,
                        placeholder: request.bodyMode == .json ? "{\n  \"name\": \"value\"\n}" : "原样发出去的内容",
                        minHeight: 110
                    )
                    if request.bodyMode == .json {
                        Text("JSON 模式会自动补上 `-H 'Content-Type: application/json'`——不补的话 curl 会按表单类型声明，后端可能拒收。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }

                case .form:
                    NetPairEditor(
                        title: "表单字段",
                        systemImage: "square.grid.2x2",
                        namePlaceholder: "字段名",
                        valuePlaceholder: "值",
                        pairs: $request.dataFields,
                        addTitle: "加字段"
                    )
                    Text("表单模式用 `--data-urlencode`，值里的中文、空格、特殊字符由 curl 负责编码，不用自己转。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)

                case .multipart:
                    VStack(alignment: .leading, spacing: 14) {
                        NetPairEditor(
                            title: "文本字段",
                            systemImage: "text.cursor",
                            namePlaceholder: "字段名",
                            valuePlaceholder: "值",
                            pairs: $request.dataFields,
                            addTitle: "加字段"
                        )
                        NetPairEditor(
                            title: "文件字段",
                            systemImage: "paperclip",
                            namePlaceholder: "字段名（如 file）",
                            valuePlaceholder: "文件路径，如 ./shot.png",
                            pairs: $request.fileFields,
                            addTitle: "加文件"
                        )
                    }
                }
            }
        }
    }

    // MARK: 认证

    private var authCard: some View {
        ToolCard(title: "认证与标识", systemImage: "person.badge.key") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("认证")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("认证", selection: $request.authMode) {
                        ForEach(CurlAuthMode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 280)
                    Spacer(minLength: 0)
                }

                if request.authMode == .basic {
                    NetLabeledField(label: "用户名", text: $request.username, width: 180)
                    NetLabeledField(label: "密码", text: $request.password, width: 180)
                } else if request.authMode == .bearer {
                    NetLabeledField(label: "Token", placeholder: "eyJhbGciOi…", text: $request.bearerToken, width: 420)
                }

                NetLabeledField(label: "Cookie", placeholder: "session=abc; theme=dark", text: $request.cookies, width: 420)
                NetLabeledField(label: "UA", placeholder: "留空则不加 -A", text: $request.userAgent, width: 420)
                NetLabeledField(label: "Referer", placeholder: "留空则不加 -e", text: $request.referer, width: 420)
            }
        }
    }

    // MARK: 开关

    private var flagsCard: some View {
        ToolCard(title: "开关", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 12) {
                FlowRow(spacing: 16) {
                    Toggle("跟随重定向 -L", isOn: $request.followRedirects).toggleStyle(.checkbox)
                    Toggle("信任自签证书 -k", isOn: $request.insecure).toggleStyle(.checkbox)
                    Toggle("压缩传输 --compressed", isOn: $request.compressed).toggleStyle(.checkbox)
                    Toggle("连响应头一起显示 -i", isOn: $request.includeHeaders).toggleStyle(.checkbox)
                    Toggle("只要响应头 -I", isOn: $request.headOnly).toggleStyle(.checkbox)
                    Toggle("安静模式 -s", isOn: $request.silent).toggleStyle(.checkbox)
                    Toggle("调试输出 -v", isOn: $request.verbose).toggleStyle(.checkbox)
                }

                HStack(alignment: .top, spacing: 16) {
                    NetLabeledField(label: "输出到", placeholder: "response.json", text: $request.outputFile, width: 220)
                    NetLabeledField(label: "连接超时", placeholder: "10", text: $request.connectTimeout, width: 90)
                    NetLabeledField(label: "总超时", placeholder: "60", text: $request.maxTime, width: 90)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: 输出

    private var outputCard: some View {
        ToolCard(title: "生成的命令", systemImage: "terminal") {
            VStack(alignment: .leading, spacing: 10) {
                TextPane(
                    title: "curl",
                    text: .constant(command),
                    isEditable: false,
                    placeholder: "填好上面的表单，命令就出现在这儿",
                    minHeight: 140,
                    buttons: [
                        PaneButton(systemImage: "doc.on.doc", help: "复制命令", action: {
                            NSPasteboard.copyString(command)
                            toast = "命令已复制"
                        }),
                        PaneButton(systemImage: "arrow.triangle.2.circlepath", help: "反解析这条命令", action: {
                            commandInput = command
                            mode = .parse
                        }),
                    ]
                )

                HStack(spacing: 8) {
                    Text("值里的单引号会按 shell 规矩写成 `'\\''`，直接粘进终端不会跑偏。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Button {
                        NSPasteboard.copyString(command)
                        toast = "命令已复制"
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                            .font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: 反解析

    private var parseCard: some View {
        ToolCard(title: "粘贴 curl 命令", systemImage: "doc.on.clipboard") {
            VStack(alignment: .leading, spacing: 12) {
                TextPane(
                    title: "命令",
                    text: $commandInput,
                    placeholder: "curl 'https://example.com/api' -X POST -H 'Content-Type: application/json' -d '{\"a\":1}'",
                    minHeight: 140,
                    buttons: [
                        PaneButton(systemImage: "doc.on.clipboard", help: "从剪贴板读取", action: {
                            if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                                commandInput = text
                                toast = "已从剪贴板读入"
                            } else {
                                toast = "剪贴板里没有文本"
                            }
                        }),
                    ]
                )

                HStack(spacing: 10) {
                    Text("认 -X/-H/-d/--data-urlencode/-F/-u/-b/-A/-e 以及 -sL 这类连写；认不出的参数会列出来，不会乱猜。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Button {
                        parse()
                    } label: {
                        Label("解析到表单", systemImage: "arrow.right.doc.on.clipboard")
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
    }

    private var warningCard: some View {
        ToolCard(title: "解析说明", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        Text(line).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
                if !unknownFlags.isEmpty {
                    NetFieldRow(label: "未识别", value: unknownFlags.joined(separator: " "), tint: .secondary)
                }
            }
        }
    }

    private func parse() {
        let result = CurlEngine.parse(commandInput)
        warnings = result.warnings
        unknownFlags = result.unknown
        request = result.request
        if request.url.isEmpty {
            toast = "没解析出 URL，检查一下命令"
            NSSound.beep()
            return
        }
        mode = .build
        toast = "已解析到表单"
    }
}
