import SwiftUI

/// 网络工具：查 IP、探连通性、发请求、拼 curl、查 DNS。
struct NetToolView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case ip
        case probe
        case http
        case curl
        case dns
        case webhook

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ip: return "IP 查询"
            case .probe: return "Ping / Telnet"
            case .http: return "HTTP 请求"
            case .curl: return "cURL"
            case .dns: return "DNS"
            case .webhook: return "Webhook"
            }
        }

        var systemImage: String {
            switch self {
            case .ip: return "globe"
            case .probe: return "waveform.path.ecg"
            case .http: return "arrow.up.arrow.down"
            case .curl: return "terminal"
            case .dns: return "magnifyingglass"
            case .webhook: return "dot.radiowaves.left.and.right"
            }
        }
    }

    @AppStorage("netMode") private var mode: Mode = .ip

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
            case .ip:
                IPLookupView()
            case .probe:
                ProbeView()
            case .http:
                HTTPRequestView()
            case .curl:
                CurlBuilderView()
            case .dns:
                DNSLookupView()
            case .webhook:
                WebhookView()
            }
        }
    }
}
