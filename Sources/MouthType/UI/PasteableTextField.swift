import AppKit
import SwiftUI

final class PasteAwareTextField: NSTextField {
    var onStringValueChanged: ((String) -> Void)?

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        onStringValueChanged?(stringValue)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == [.command], let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "v":
                pasteFromClipboard()
                return
            case "a":
                currentEditor()?.selectAll(self)
                return
            case "c":
                currentEditor()?.copy(self)
                return
            case "x":
                currentEditor()?.cut(self)
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == [.command], let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "v":
            pasteFromClipboard()
            return true
        case "a":
            currentEditor()?.selectAll(self)
            return true
        case "c":
            currentEditor()?.copy(self)
            return true
        case "x":
            currentEditor()?.cut(self)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            NSSound.beep()
            return
        }

        // 先尝试使用当前编辑器
        if let editor = currentEditor() as? NSTextView {
            editor.insertText(text, replacementRange: editor.selectedRange())
            onStringValueChanged?(editor.string)
            return
        }

        // 如果没有编辑器，直接设置值并触发通知
        let oldString = stringValue
        stringValue = text
        if oldString != stringValue {
            onStringValueChanged?(stringValue)
        }
    }
}

final class PasteAwareSecureTextField: NSSecureTextField {
    var onStringValueChanged: ((String) -> Void)?

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        onStringValueChanged?(stringValue)
    }

    override func keyDown(with event: NSEvent) {
        if handlePasteShortcut(event) {
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handlePasteShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func handlePasteShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == [.command], event.charactersIgnoringModifiers?.lowercased() == "v" else {
            return false
        }

        pasteFromClipboard()
        return true
    }

    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            NSSound.beep()
            return
        }

        // 先尝试使用当前编辑器
        if let editor = currentEditor() as? NSTextView {
            editor.insertText(text, replacementRange: editor.selectedRange())
            onStringValueChanged?(editor.string)
            return
        }

        // 如果没有编辑器，直接设置值并触发通知
        let oldString = stringValue
        stringValue = text
        if oldString != stringValue {
            onStringValueChanged?(stringValue)
        }
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
