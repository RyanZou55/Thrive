import SwiftUI

/// 可编辑的备注框。生长记录和养护记录的详情页共用。
struct NoteEditor: View {
    @Binding var text: String
    var placeholder: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("备注")
                .font(.subheadline.weight(.medium))
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)
        }
    }
}
