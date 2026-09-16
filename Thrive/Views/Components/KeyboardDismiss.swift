import SwiftUI
import UIKit

extension View {
    /// 有键盘的时候，点页面空白处收起来。挂在根视图上一次就够，sheet 和全屏页也一起管到。
    ///
    /// 试过纯 SwiftUI 的做法，两条路都不通：手势垫在 ScrollView 后面收不到点击，
    /// 而 contentShape + onTapGesture 加到 Form 上会把行里按钮的点击吃掉。
    /// 所以退到 UIKit —— 在 window 上挂一个只旁听、不截胡的识别器。
    func dismissesKeyboardOnTap() -> some View {
        background {
            KeyboardDismissTapCatcher()
                .frame(width: 0, height: 0)
        }
    }
}

/// cancelsTouchesInView = false 是关键：触摸照常发给按钮和输入框，
/// 这个识别器只是在旁边跟着响一下，不改变任何控件原本的行为。
private struct KeyboardDismissTapCatcher: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        // 刚创建时还没上屏，window 是 nil，下一轮 runloop 再挂。
        DispatchQueue.main.async {
            guard context.coordinator.recognizer == nil, let window = view.window else { return }
            let tap = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleTap)
            )
            tap.cancelsTouchesInView = false
            tap.delegate = context.coordinator
            window.addGestureRecognizer(tap)
            context.coordinator.recognizer = tap
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var recognizer: UITapGestureRecognizer?

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            gesture.view?.endEditing(true)
        }

        /// 点在输入框自己身上时不收：否则刚点进去就被收掉，
        /// 两个输入框之间也没法直接切过去。
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            !(touch.view?.isInsideTextInput ?? false)
        }
    }
}

private extension UIView {
    /// 自己或者往上数的任一层是不是文本输入控件。
    var isInsideTextInput: Bool {
        var view: UIView? = self
        while let current = view {
            if current is UITextField || current is UITextView { return true }
            view = current.superview
        }
        return false
    }
}
