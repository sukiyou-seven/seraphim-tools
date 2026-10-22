import AppKit
import SwiftUI

/// 提示词：模板库 / 压缩 / 扩写。
///
/// 三段解决的是三件事——把常用写法存下来、把啰嗦的删掉、把太短的补起来。
struct PromptToolView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case library
        case compress
        case expand

        var id: String { rawValue }

        var title: String {
            switch self {
            case .library: return "模板库"
            case .compress: return "压缩"
            case .expand: return "扩写"
            }
        }
    }

    @AppStorage("promptMode") private var mode: Mode = .library

    var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            switch mode {
            case .library:
                PromptLibraryPanel()
            case .compress:
                PromptCompressPanel()
            case .expand:
                PromptExpandPanel()
            }
        }
    }
}
