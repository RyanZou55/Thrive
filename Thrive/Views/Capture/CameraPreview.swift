import AVFoundation
import SwiftUI

/// 把 AVCaptureSession 的实时画面塞进 SwiftUI。
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
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
    }
}
