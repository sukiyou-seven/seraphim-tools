import SwiftUI

/// 开发辅助：四个日常用得到的家伙事儿凑一块儿。
struct DevToolView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case timestamp
        case color
        case chinese
        case regex
        case port

        var id: String { rawValue }

        var title: String {
            switch self {
            case .timestamp: return "时间戳"
            case .color: return "颜色"
            case .chinese: return "中国色"
            case .regex: return "正则"
            case .port: return "端口"
            }
        }

        var systemImage: String {
            switch self {
            case .timestamp: return "clock"
            case .color: return "paintpalette"
            case .chinese: return "circle.grid.3x3"
            case .regex: return "text.magnifyingglass"
            case .port: return "network"
            }
        }
    }

    @AppStorage("devMode") private var mode: Mode = .timestamp

    var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Label(item.title, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            switch mode {
            case .timestamp:
                TimestampView()
            case .color:
                ColorToolView()
            case .chinese:
                ChineseColorView()
            case .regex:
                RegexToolView()
            case .port:
                PortScanView()
            }
        }
    }
}
