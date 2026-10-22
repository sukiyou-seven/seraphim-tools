import AVFoundation
import AppKit
import Combine
import CoreImage
import SwiftUI
import Vision

/// 摄像头实时扫码。
///
/// 采集跑在后台队列，Vision 解码做了节流（默认 4 次/秒），命中后回主线程回调。
final class CameraScanner: NSObject, ObservableObject {

    enum Status: Equatable {
        case idle
        case requesting
        case running
        case denied
        case unavailable(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastResult: CodeScanResult?

    let session = AVCaptureSession()

    /// 命中新码时的回调，保证在主线程
    var onDetect: ((CodeScanResult) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.seraphim.tools.camera.session")
    private let videoQueue = DispatchQueue(label: "com.seraphim.tools.camera.video")
    private var isConfigured = false
    private var lastScanTime = Date.distantPast
    private let scanInterval: TimeInterval = 0.25

    var isRunning: Bool { status == .running }

    // MARK: - 生命周期

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            status = .requesting
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if granted {
                        self.configureAndStart()
                    } else {
                        self.status = .denied
                    }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
            DispatchQueue.main.async { [weak self] in
                if self?.status == .running { self?.status = .idle }
            }
        }
    }

    func refreshAuthorization() {
        let current = AVCaptureDevice.authorizationStatus(for: .video)
        if current == .authorized, status == .denied {
            configureAndStart()
        } else if current != .authorized, status == .running {
            stop()
        }
    }

    // MARK: - 私有

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if !self.isConfigured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .high

                guard let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.status = .unavailable("找不到可用的摄像头") }
                    return
                }
                self.session.addInput(input)

                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                output.setSampleBufferDelegate(self, queue: self.videoQueue)
                if self.session.canAddOutput(output) {
                    self.session.addOutput(output)
                }

                self.session.commitConfiguration()
                self.isConfigured = true
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async { self.status = .running }
        }
    }
}

extension CameraScanner: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastScanTime) >= scanInterval else { return }
        lastScanTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])

        guard let observation = request.results?.first,
              let payload = observation.payloadStringValue,
              !payload.isEmpty else { return }

        let result = CodeScanResult(
            payload: payload,
            symbology: "QR Code",
            confidence: observation.confidence,
            boundingBox: observation.boundingBox,
            source: "摄像头"
        )

        DispatchQueue.main.async { [weak self] in
            self?.lastResult = result
            self?.onDetect?(result)
        }
    }
}

/// AVCaptureVideoPreviewLayer 的 SwiftUI 包装
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(session: session)
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        if nsView.previewLayer.session !== session {
            nsView.previewLayer.session = session
        }
    }

    final class PreviewView: NSView {
        let previewLayer: AVCaptureVideoPreviewLayer

        init(session: AVCaptureSession) {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            previewLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
