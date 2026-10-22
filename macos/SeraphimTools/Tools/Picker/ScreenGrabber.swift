import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 屏幕抓取。`CGDisplayCreateImage` 在 macOS 15 已经废弃，这里走 ScreenCaptureKit。
///
/// 屏幕录制属于系统隐私权限，没授权时抓到的是桌面壁纸而不是真实画面，
/// 所以调用前一定要先 `hasPermission` 探一下，别让用户对着黑图取色。
enum ScreenGrabber {

    static var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 弹系统授权请求（首次会弹窗，之后直接跳到系统设置里的对应开关）
    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    enum GrabError: LocalizedError {
        case noDisplay
        case unavailable

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "没找到可以截取的显示器"
            case .unavailable: return "这个功能需要 macOS 14 或更高版本"
            }
        }
    }

    @available(macOS 14.0, *)
    static func captureMainDisplay() async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let mainID = CGMainDisplayID()
        let display = content.displays.first { $0.displayID == mainID } ?? content.displays.first
        guard let display else { throw GrabError.noDisplay }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false
        configuration.captureResolution = .best

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// 截图，顺便把主屏像素尺寸一起带回来（界面里要用它换算坐标）
    static func grab() async throws -> (image: CGImage, pixelSize: CGSize, scale: CGFloat) {
        guard #available(macOS 14.0, *) else { throw GrabError.unavailable }
        let image = try await captureMainDisplay()
        let screenWidth = NSScreen.main?.frame.width ?? CGFloat(image.width)
        let scale = screenWidth > 0 ? CGFloat(image.width) / screenWidth : 1
        return (image, CGSize(width: image.width, height: image.height), scale)
    }
}
