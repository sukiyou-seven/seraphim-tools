import SwiftUI

struct CryptoToolView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case hash
        case checksum
        case symmetric
        case classic
        case random
        case jwt

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hash: return "摘要"
            case .checksum: return "校验和"
            case .symmetric: return "对称加密"
            case .classic: return "古典密码"
            case .random: return "随机生成"
            case .jwt: return "JWT"
            }
        }

        var systemImage: String {
            switch self {
            case .hash: return "number.square"
            case .checksum: return "checkmark.shield"
            case .symmetric: return "lock.shield"
            case .classic: return "scroll"
            case .random: return "dice"
            case .jwt: return "person.badge.key"
            }
        }
    }

    @AppStorage("cryptoMode") private var mode: Mode = .hash

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
            case .hash:
                CryptoHashView()
            case .checksum:
                CryptoChecksumView()
            case .symmetric:
                CryptoSymmetricView()
            case .classic:
                CryptoClassicView()
            case .random:
                CryptoRandomView()
            case .jwt:
                JWTPanel()
            }
        }
    }
}
