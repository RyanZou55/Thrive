import AVFoundation
import Combine
import OSLog
import UIKit

/// 相机会话。负责预览、拍照，以及权限。
@MainActor
final class CameraService: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case ready
        case denied
        case unavailable(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var isCapturing = false
    /// 刚拍下来的照片，拍完由 CaptureView 取走。
    @Published var capturedImage: UIImage?

    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.ryanzou.thrive.camera")
    private var isConfigured = false
    private let logger = Logger(subsystem: "com.ryanzou.thrive", category: "Camera")

    // MARK: - 生命周期

    /// 请权限 → 配置会话 → 跑起来。可以重复调用。
    func start() async {
        guard await ensureAuthorized() else {
            status = .denied
            return
        }

        guard configureIfNeeded() else { return }

        status = .ready
        sessionQueue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    // MARK: - 权限

    private func ensureAuthorized() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    // MARK: - 配置

    private func configureIfNeeded() -> Bool {
        guard !isConfigured else { return true }

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            // 模拟器走这条路。UI 会退回「从相册选择」。
            status = .unavailable("这台设备上没有可用的相机")
            logger.info("找不到后置广角相机")
            return false
        }

        session.beginConfiguration()
        session.sessionPreset = .photo

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                status = .unavailable("无法接入相机输入")
                return false
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            status = .unavailable(error.localizedDescription)
            logger.error("创建相机输入失败: \(error.localizedDescription, privacy: .public)")
            return false
        }

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            status = .unavailable("无法接入照片输出")
            return false
        }
        session.addOutput(photoOutput)
        session.commitConfiguration()

        isConfigured = true
        return true
    }

    // MARK: - 拍照

    func capturePhoto() {
        guard case .ready = status, !isCapturing else { return }
        isCapturing = true

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        // 输出方向跟着 UI 走：App 锁死竖屏，所以固定竖屏即可。
        if let connection = photoOutput.connection(with: .video) {
            if #available(iOS 17.0, *), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image: UIImage? = {
            guard error == nil, let data = photo.fileDataRepresentation() else { return nil }
            return UIImage(data: data)
        }()

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isCapturing = false
            if let image {
                self.capturedImage = image
            } else if let error {
                self.logger.error("拍照失败: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
