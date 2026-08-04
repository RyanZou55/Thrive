import SwiftUI
import UIKit

/// 系统相机，拍完直接把图交回来。
///
/// 浇水只是随手拍一张留个记录，不需要生长照那套幽灵叠影 / 姿态对齐，
/// 所以这里用系统自带的拍照界面，不走 CaptureView。
struct CameraPicker: UIViewControllerRepresentable {
    /// 拍完或取消都会回调，取消时传 nil。调用方负责关闭 sheet。
    var onFinish: (UIImage?) -> Void

    /// 模拟器没有相机，用来决定要不要显示「拍照」这个选项。
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
