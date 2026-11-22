import SwiftUI
import UIKit
import GameController

/// Diagnostic for "the software keyboard never appears". Three fields (SwiftUI, SwiftUI with
/// @FocusState, and a bare UIKit UITextField) plus live keyboard notifications and the system's
/// view of any hardware keyboard. If the UIKit field fails too, the cause is outside our SwiftUI code.
struct KeyboardTestView: View {
    @State private var plain = ""
    @State private var focused = ""
    @State private var uikit = ""
    @FocusState private var focusedField: Bool
    @State private var events: [String] = []
    @State private var hardwareKeyboard = GCKeyboard.coalesced != nil

    var body: some View {
        Form {
            Section("1 · SwiftUI TextField") {
                TextField("Tap and type here", text: $plain)
            }
            Section("2 · SwiftUI TextField + @FocusState") {
                TextField("Focused by the button below", text: $focused)
                    .focused($focusedField)
                Button("Focus field 2 in code") { focusedField = true }
            }
            Section("3 · Plain UIKit UITextField") {
                UIKitTextField(text: $uikit)
                    .frame(height: 36)
            }
            Section("What the system reports") {
                LabeledContent("Hardware keyboard", value: hardwareKeyboard ? "CONNECTED" : "none")
                LabeledContent("Idiom", value: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "other")
                LabeledContent("Key window", value: UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first == nil ? "none" : "present")
            }
            Section("Keyboard events (will show / did show / will hide)") {
                if events.isEmpty { Text("None yet. Tap a field.").foregroundStyle(.secondary) }
                ForEach(Array(events.enumerated()), id: \.offset) { _, e in
                    Text(e).font(.system(.footnote, design: .monospaced))
                }
            }
        }
        .navigationTitle("Keyboard test")
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in note("will show") }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in note("did show") }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in note("will hide") }
        .onReceive(NotificationCenter.default.publisher(for: .GCKeyboardDidConnect)) { _ in hardwareKeyboard = true }
        .onReceive(NotificationCenter.default.publisher(for: .GCKeyboardDidDisconnect)) { _ in hardwareKeyboard = false }
    }

    private func note(_ text: String) {
        events.insert("\(Date().formatted(date: .omitted, time: .standard)) \(text)", at: 0)
        AppLog.shared.info("keyboard: \(text)")
    }
}

private struct UIKitTextField: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.borderStyle = .roundedRect
        field.placeholder = "UIKit field: tap and type"
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        if field.text != text { field.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        @objc func changed(_ field: UITextField) { text.wrappedValue = field.text ?? "" }
    }
}
