import Foundation
import Combine

/// 跨工具、跨页面的轻量全局状态
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// 从 Finder 双击 / open 命令进来的图片，等待图像工具取走
    @Published var pendingImageURL: URL?

    private init() {}

    func enqueue(imageURL: URL) {
        pendingImageURL = imageURL
    }

    func takePendingImageURL() -> URL? {
        defer { pendingImageURL = nil }
        return pendingImageURL
    }
}

extension Notification.Name {
    /// 请求切换到「图像处理」工具
    static let focusImageTool = Notification.Name("SeraphimTools.focusImageTool")
}
