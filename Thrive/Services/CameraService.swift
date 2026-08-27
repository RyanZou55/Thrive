// AVCaptureSession 等类型还没标 Sendable，但按苹果的用法约定，
// 把会话操作丢到自己的串行队列上是安全的。@preconcurrency 用来消掉这类噪音警告。
@preconcurrency import AVFoundation
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

    /// 录制中的一段转盘视频，停录后由 CaptureView 取走抽帧。
    @Published private(set) var isRecording = false
    @Published var recordedMovieURL: URL?

    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "com.ryanzou.thrive.camera")
    private var isConfigured = false
    private var videoDevice: AVCaptureDevice?
    /// 录制真正开始那一刻的 uptime。yaw 轨迹靠它对到视频时间轴上。
    private(set) var recordingStartUptime: TimeInterval?
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
            status = .unavailable(String(localized: "这台设备上没有可用的相机"))
            logger.info("找不到后置广角相机")
            return false
        }

        videoDevice = device

        session.beginConfiguration()
        session.sessionPreset = .photo

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                status = .unavailable(String(localized: "无法接入相机输入"))
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
            status = .unavailable(String(localized: "无法接入照片输出"))
            return false
        }
        session.addOutput(photoOutput)

        // 转盘录像用。不接音频输入 —— 转盘不需要声音，
        // 也就不用多要一次麦克风权限。
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        } else {
            logger.error("无法接入视频输出，转盘拍摄会不可用")
        }

        session.commitConfiguration()

        isConfigured = true
        return true
    }

    // MARK: - 转盘录制

    /// 开录。先锁曝光和白平衡 —— 绕一圈光照方向变化很大，
    /// 让它自动跟着调的话，转起来会一帧亮一帧暗，闪得很难看。
    func startSpinRecording() {
        guard case .ready = status, !isRecording else { return }

        // .photo preset 下录像输出不保证可用，先切到视频 preset。
        applySpinPreset()
        // 只看连接在不在，不看 isActive —— 刚 commit 完配置时 isActive 还没稳定，
        // 拿它当前置条件会误判成「录不了」。真起不来会走 didFinishRecording 的错误分支。
        guard movieOutput.connection(with: .video) != nil else {
            logger.error("没有视频连接，转盘录不了")
            restorePhotoPreset()
            return
        }

        lockExposureAndWhiteBalance()
        applyPortraitRotation(to: movieOutput.connection(with: .video))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spin-\(UUID().uuidString).mov")
        isRecording = true
        recordedMovieURL = nil
        recordingStartUptime = nil
        movieOutput.startRecording(to: url, recordingDelegate: self)
    }

    func stopSpinRecording() {
        guard isRecording else { return }
        movieOutput.stopRecording()
    }

    /// 抽完帧后把临时视频删掉，不留双份。
    func discardRecordedMovie() {
        guard let recordedMovieURL else { return }
        try? FileManager.default.removeItem(at: recordedMovieURL)
        self.recordedMovieURL = nil
    }

    /// 4K 优先，不支持就退 1080p —— 长边 1920 抽帧到 1280 还有余量。
    private func applySpinPreset() {
        let preferred: [AVCaptureSession.Preset] = [.hd4K3840x2160, .hd1920x1080]
        guard let preset = preferred.first(where: { session.canSetSessionPreset($0) }) else { return }
        session.beginConfiguration()
        session.sessionPreset = preset
        session.commitConfiguration()
    }

    /// 录完切回去，不然退出转盘模式后拍单张的画质会一直是视频那档。
    private func restorePhotoPreset() {
        guard session.sessionPreset != .photo else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        session.commitConfiguration()
    }

    private func lockExposureAndWhiteBalance() {
        guard let videoDevice, (try? videoDevice.lockForConfiguration()) != nil else { return }
        if videoDevice.isExposureModeSupported(.locked) {
            videoDevice.exposureMode = .locked
        }
        if videoDevice.isWhiteBalanceModeSupported(.locked) {
            videoDevice.whiteBalanceMode = .locked
        }
        videoDevice.unlockForConfiguration()
    }

    /// 录完恢复自动，否则退出转盘模式后取景会一直卡在刚才那档曝光。
    private func unlockExposureAndWhiteBalance() {
        guard let videoDevice, (try? videoDevice.lockForConfiguration()) != nil else { return }
        if videoDevice.isExposureModeSupported(.continuousAutoExposure) {
            videoDevice.exposureMode = .continuousAutoExposure
        }
        if videoDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            videoDevice.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        videoDevice.unlockForConfiguration()
    }

    /// App 锁死竖屏，输出方向固定跟着走。
    private func applyPortraitRotation(to connection: AVCaptureConnection?) {
        guard let connection else { return }
        if #available(iOS 17.0, *), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    // MARK: - 拍照

    func capturePhoto() {
        guard case .ready = status, !isCapturing else { return }
        isCapturing = true

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        applyPortraitRotation(to: photoOutput.connection(with: .video))
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

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        // 这个回调和第一帧画面之间有几十毫秒延迟，也就是说所有帧会整体偏个一度左右。
        // 但那是个恒定偏移 —— 帧和帧之间的间隔不受影响，而转起来顺不顺只看间隔。
        let uptime = ProcessInfo.processInfo.systemUptime
        Task { @MainActor [weak self] in
            self?.recordingStartUptime = uptime
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isRecording = false
            self.unlockExposureAndWhiteBalance()
            self.restorePhotoPreset()

            if let error {
                self.logger.error("转盘录制失败: \(error.localizedDescription, privacy: .public)")
                try? FileManager.default.removeItem(at: outputFileURL)
                return
            }
            self.recordedMovieURL = outputFileURL
        }
    }
}
