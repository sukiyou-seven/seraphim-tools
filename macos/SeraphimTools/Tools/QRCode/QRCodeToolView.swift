import SwiftUI

struct QRCodeToolView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case generate = "生成"
        case scan = "识别"
        var id: String { rawValue }
    }

    @AppStorage("qrcodeMode") private var mode: Mode = .generate

    var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            switch mode {
            case .generate:
                QRCodeGenerateView()
            case .scan:
                QRCodeScanView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
