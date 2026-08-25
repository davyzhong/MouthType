import AppKit
import SwiftUI

// MARK: - Paste-aware NSTextField
// 在 NSViewRepresentable 中，系统 responder chain 不工作，
// 所以必须在 performKeyEquivalent 中拦截 Cmd+V/C/X/A 并直接操作 self。

final class PasteAwareTextField: NSTextField {
    var onStringValueChanged: ((String) -> Void)?

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        onStringValueChanged?(stringValue)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command],
              let key = event.charactersIgnoringModifiers?.lowercased()
        else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "v":
            pasteIntoSelf()
            return true
        case "c":
            copyFromSelf()
            return true
        case "x":
            cutFromSelf()
            return true
        case "a":
            selectAllInSelf()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    private func pasteIntoSelf() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            NSSound.beep()
            return
        }
        stringValue = text
    }

    private func copyFromSelf() {
        if let editor = currentEditor(), editor.selectedRange.length > 0 {
            editor.copy(nil)
        } else if !stringValue.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(stringValue, forType: .string)
        }
    }

    private func cutFromSelf() {
        if let editor = currentEditor(), editor.selectedRange.length > 0 {
            editor.cut(nil)
        }
    }

    private func selectAllInSelf() {
        currentEditor()?.selectAll(self)
    }
}

// MARK: - Paste-aware NSSecureTextField

final class PasteAwareSecureTextField: NSSecureTextField {
    var onStringValueChanged: ((String) -> Void)?

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        onStringValueChanged?(stringValue)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command],
              let key = event.charactersIgnoringModifiers?.lowercased()
        else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "v":
            pasteIntoSelf()
            return true
        case "c":
            copyFromSelf()
            return true
        case "x":
            cutFromSelf()
            return true
        case "a":
            selectAllInSelf()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    private func pasteIntoSelf() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            NSSound.beep()
            return
        }
        stringValue = text
    }

    private func copyFromSelf() {
        if let editor = currentEditor(), editor.selectedRange.length > 0 {
            editor.copy(nil)
        } else if !stringValue.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(stringValue, forType: .string)
        }
    }

    private func cutFromSelf() {
        if let editor = currentEditor(), editor.selectedRange.length > 0 {
            editor.cut(nil)
        }
    }

    private func selectAllInSelf() {
        currentEditor()?.selectAll(self)
    }
}

struct PasteableTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let accessibilityIdentifier: String?

    init(placeholder: String, text: Binding<String>, accessibilityIdentifier: String? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = PasteAwareTextField()
        field.placeholderString = placeholder
        field.stringValue = text
        field.delegate = context.coordinator
        field.onStringValueChanged = { value in
            context.coordinator.parent.text = value
        }
        field.bezelStyle = .roundedBezel
        field.isBordered = true
        field.drawsBackground = true
        field.isEditable = true
        field.isSelectable = true
        field.translatesAutoresizingMaskIntoConstraints = false
        if let accessibilityIdentifier {
            field.setAccessibilityIdentifier(accessibilityIdentifier)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if let field = nsView as? PasteAwareTextField {
            field.onStringValueChanged = { value in
                context.coordinator.parent.text = value
            }
        }
        nsView.placeholderString = placeholder
        if let accessibilityIdentifier {
            nsView.setAccessibilityIdentifier(accessibilityIdentifier)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PasteableTextField

        init(_ parent: PasteableTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

struct PasteableSecureField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let accessibilityIdentifier: String?

    init(placeholder: String, text: Binding<String>, accessibilityIdentifier: String? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = PasteAwareSecureTextField()
        field.placeholderString = placeholder
        field.stringValue = text
        field.delegate = context.coordinator
        field.onStringValueChanged = { value in
            context.coordinator.parent.text = value
        }
        field.bezelStyle = .roundedBezel
        field.isBordered = true
        field.drawsBackground = true
        field.isEditable = true
        field.isSelectable = true
        field.translatesAutoresizingMaskIntoConstraints = false
        if let accessibilityIdentifier {
            field.setAccessibilityIdentifier(accessibilityIdentifier)
        }
        return field
    }

    func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if let field = nsView as? PasteAwareSecureTextField {
            field.onStringValueChanged = { value in
                context.coordinator.parent.text = value
            }
        }
        nsView.placeholderString = placeholder
        if let accessibilityIdentifier {
            nsView.setAccessibilityIdentifier(accessibilityIdentifier)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PasteableSecureField

        init(_ parent: PasteableSecureField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}
