import SwiftUI

/// 原型 & 低代码辅助：需求 → 页面 → 组件 → 流程。
///
/// 四段串起来的是一条完整路径：先把想法写成 AI 能接住的需求，再把需求落到具体页面，
/// 页面里的零件单独出规格，最后把有分支的流程画出来。
/// 每一段的产物都是「一段可以直接粘给 AI 的文字」——这是这个工具存在的全部理由。
struct ProtoToolView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case requirement
        case page
        case component
        case flow

        var id: String { rawValue }

        var title: String {
            switch self {
            case .requirement: return "需求"
            case .page: return "页面"
            case .component: return "组件"
            case .flow: return "流程图"
            }
        }

        var systemImage: String {
            switch self {
            case .requirement: return "lightbulb"
            case .page: return "rectangle.3.group"
            case .component: return "square.on.square"
            case .flow: return "arrow.triangle.branch"
            }
        }
    }

    @AppStorage("protoMode") private var mode: Mode = .requirement

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
            case .requirement:
                ProtoRequirementPanel()
            case .page:
                ProtoPagePanel()
            case .component:
                ProtoComponentPanel()
            case .flow:
                ProtoFlowPanel()
            }
        }
    }
}
