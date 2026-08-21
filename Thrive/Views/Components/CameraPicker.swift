import SwiftUI
import UIKit

/// 系统相机，拍完直接把图交回来。
///
/// 只给「添加植物」时拍封面用：那会儿植物还没建出来，也没有上一张照片，
/// CaptureView 那套幽灵叠影 / 姿态对齐无从谈起，用系统拍照界面就够了。
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
