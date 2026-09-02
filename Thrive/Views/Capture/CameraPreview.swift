import AVFoundation
import SwiftUI

/// 把 AVCaptureSession 的实时画面塞进 SwiftUI。
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// 取景框的宽高比（宽 / 高），布局变化时报上来。
    /// 画面是 resizeAspectFill 裁过的，照片得按同一个比例裁才对得上。
    var onAspectRatioChange: (CGFloat) -> Void = { _ in }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.onAspectRatioChange = onAspectRatioChange
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.onAspectRatioChange = onAspectRatioChange
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
    }

    /// layerClass 用 AVCaptureVideoPreviewLayer，尺寸变化由 UIKit 自己跟，不用手动同步 frame。
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // layerClass 已经指定过类型，这里必然成立。
            layer as! AVCaptureVideoPreviewLayer
        }

        var onAspectRatioChange: (CGFloat) -> Void = { _ in }
        private var reportedAspectRatio: CGFloat?

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width > 0, bounds.height > 0 else { return }
            let ratio = bounds.width / bounds.height
            guard reportedAspectRatio != ratio else { return }
            reportedAspectRatio = ratio
            onAspectRatioChange(ratio)
        }
    }
}
