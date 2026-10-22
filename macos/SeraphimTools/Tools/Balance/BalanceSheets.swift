import SwiftUI

// MARK: - 填 Key

struct BalanceKeySheet: View {
    let provider: BalanceProvider
    let existingMask: String?

    var onSave: (String) -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerBlock
            privacyBlock
            inputBlock
            actionBlock
        }
        .padding(20)
        .frame(width: 470)
    }

    private var headerBlock: some View {
        HStack(spacing: 10) {
            BalanceBadge(provider: provider, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("API Key · \(provider.name)")
                    .font(.system(size: 14, weight: .semibold))
                Text(provider.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var privacyBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Key 存进 macOS 钥匙串，不写进任何配置文件，界面上只显示掩码。检测时只发给 \(provider.domain)。", systemImage: "lock.shield")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Link(destination: URL(string: provider.keyPageURL) ?? URL(string: "https://example.com")!) {
                    Label("去申请 / 查看 Key", systemImage: "arrow.up.right.square")
                        .font(.system(size: 11))
                }
                if !provider.keyPlaceholder.isEmpty {
                    Text("格式：\(provider.keyPlaceholder)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var inputBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API Key")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Group {
                    if revealed {
                        TextField("粘贴 API Key", text: $draft)
                    } else {
                        SecureField("粘贴 API Key", text: $draft)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit(submit)

                Button {
                    revealed.toggle()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(revealed ? "隐藏" : "显示")

                Button("粘贴") {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        draft = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                .font(.system(size: 11))
            }

            if let existingMask {
                Text("当前已存：\(existingMask)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var actionBlock: some View {
        HStack(spacing: 10) {
            if existingMask != nil {
                Button("删除已存的 Key", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                .font(.system(size: 11.5))
            }
            Spacer(minLength: 0)
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("保存并检测", action: submit)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func submit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}

// MARK: - 自定义厂商

struct BalanceCustomSheet: View {
    @State private var draft: CustomProvider
    private let isNew: Bool

    var onSave: (CustomProvider) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var headerText: String

    init(seed: CustomProvider, isNew: Bool, onSave: @escaping (CustomProvider) -> Void) {
        _draft = State(initialValue: seed)
        _headerText = State(initialValue: BalanceEngine.formatHeaders(seed.extraHeaders))
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "添加自定义厂商" : "编辑自定义厂商")
                .font(.system(size: 14, weight: .semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    nameField
                    addressFields
                    optionFields
                    headerField
                }
                .padding(.trailing, 4)
            }
            .frame(maxHeight: 400)

            HStack {
                Spacer(minLength: 0)
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    var item = draft
                    item.extraHeaders = BalanceEngine.parseHeaders(headerText)
                    onSave(item)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 500)
    }

    private var isValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.balanceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var nameField: some View {
        LabeledField(title: "名称", hint: "随便起，只影响显示") {
            TextField("比如：公司中转站", text: $draft.name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var addressFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledField(title: "余额查询地址", hint: "可以写完整 URL，也可以只写路径") {
                TextField("https://api.example.com/v1/user/balance", text: $draft.balanceURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
            LabeledField(title: "Base URL", hint: "只有当上面写的是相对路径时才用得上") {
                TextField("https://api.example.com", text: $draft.baseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
        }
    }

    private var optionFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LabeledField(title: "请求方法") {
                    Picker("", selection: $draft.method) {
                        Text("GET").tag("GET")
                        Text("POST").tag("POST")
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
                LabeledField(title: "Key 放在") {
                    Picker("", selection: $draft.authRaw) {
                        ForEach(BalanceAuthStyle.allCases, id: \.rawValue) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                LabeledField(title: "解析方式") {
                    Picker("", selection: $draft.parser) {
                        Text("自动识别金额字段").tag("generic")
                        Text("one-api / new-api（quota÷500000）").tag("oneapi")
                    }
                    .labelsHidden()
                    .frame(width: 260)
                }
                LabeledField(title: "币种") {
                    Picker("", selection: $draft.currency) {
                        Text("CNY").tag("CNY")
                        Text("USD").tag("USD")
                        Text("EUR").tag("EUR")
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var headerField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("额外请求头")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextEditor(text: $headerText)
                .font(.system(size: 11, design: .monospaced))
                .frame(height: 58)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10))
                )
            Text("一行一个 `名字: 值`。one-api / new-api 自建站通常要带 `New-Api-User: 你的用户ID`，而且要填**系统设置里的访问令牌**，不是 sk- 开头的那个 key。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
