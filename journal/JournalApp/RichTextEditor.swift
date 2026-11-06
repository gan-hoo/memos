import SwiftUI
import UIKit

/// 控制正文 UITextView 的格式操作
@MainActor
final class RichTextController: ObservableObject {
    weak var textView: UITextView?

    enum Style: CaseIterable, Identifiable {
        case title, heading, body
        var id: Self { self }
        var name: String {
            switch self {
            case .title: return "标题"
            case .heading: return "小标题"
            case .body: return "正文"
            }
        }
        var font: UIFont {
            switch self {
            case .title: return .systemFont(ofSize: 24, weight: .bold)
            case .heading: return .systemFont(ofSize: 19, weight: .semibold)
            case .body: return .preferredFont(forTextStyle: .body)
            }
        }
    }

    nonisolated static var baseFont: UIFont { .preferredFont(forTextStyle: .body) }

    nonisolated static var textColors: [UIColor] {
        [.label, .systemRed, .systemOrange, .systemGreen, .systemBlue, .systemPurple]
    }

    // MARK: 加粗 / 斜体 / 下划线 / 删除线

    func toggleBold() { toggleFontTrait(.traitBold) }

    func toggleItalic() { toggleAttribute(.obliqueness, on: 0.2 as NSNumber) }

    func toggleUnderline() { toggleAttribute(.underlineStyle, on: NSUnderlineStyle.single.rawValue as NSNumber) }

    func toggleStrikethrough() { toggleAttribute(.strikethroughStyle, on: NSUnderlineStyle.single.rawValue as NSNumber) }

    func setColor(_ color: UIColor) {
        guard let tv = textView else { return }
        let r = tv.selectedRange
        if r.length == 0 {
            tv.typingAttributes[.foregroundColor] = color
            return
        }
        tv.textStorage.addAttribute(.foregroundColor, value: color, range: r)
        changed(tv)
    }

    func setStyle(_ style: Style) {
        guard let tv = textView else { return }
        let ns = tv.textStorage.string as NSString
        let para = ns.length == 0 ? NSRange(location: 0, length: 0) : ns.paragraphRange(for: tv.selectedRange)
        tv.typingAttributes[.font] = style.font
        guard para.length > 0 else { return }
        tv.textStorage.addAttribute(.font, value: style.font, range: para)
        changed(tv)
    }

    /// 切换项目符号列表（作用于所选段落）
    func toggleBullets() { togglePrefix("• ") }

    func toggleQuote() { togglePrefix("｜") }

    func find() {
        guard let tv = textView else { return }
        tv.becomeFirstResponder()
        tv.findInteraction?.presentFindNavigator(showingReplace: false)
    }

    // MARK: - 内部

    private func togglePrefix(_ prefix: String) {
        guard let tv = textView else { return }
        let storage = tv.textStorage
        let ns = storage.string as NSString
        let selection = tv.selectedRange
        let para = ns.length == 0 ? NSRange(location: 0, length: 0) : ns.paragraphRange(for: selection)
        let lines = (ns.substring(with: para) as NSString)
        var lineRanges: [NSRange] = []
        lines.enumerateSubstrings(in: NSRange(location: 0, length: lines.length), options: [.byParagraphs, .substringNotRequired]) { _, r, _, _ in
            lineRanges.append(NSRange(location: r.location + para.location, length: r.length))
        }
        if lineRanges.isEmpty { lineRanges = [NSRange(location: para.location, length: 0)] }

        let allHave = lineRanges.allSatisfy { ns.substring(with: $0).hasPrefix(prefix) }
        let attrs = tv.typingAttributes
        storage.beginEditing()
        var delta = 0
        for r in lineRanges.reversed() {
            if allHave {
                storage.deleteCharacters(in: NSRange(location: r.location, length: (prefix as NSString).length))
                delta -= (prefix as NSString).length
            } else if !ns.substring(with: r).hasPrefix(prefix) {
                storage.insert(NSAttributedString(string: prefix, attributes: attrs), at: r.location)
                delta += (prefix as NSString).length
            }
        }
        storage.endEditing()
        tv.selectedRange = NSRange(location: max(0, selection.location + (lineRanges.count == 1 ? delta : 0)), length: selection.length)
        changed(tv)
    }

    private func toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let tv = textView else { return }
        let r = tv.selectedRange
        let base = Self.baseFont
        if r.length == 0 {
            let f = (tv.typingAttributes[.font] as? UIFont) ?? base
            tv.typingAttributes[.font] = f.with(trait, on: !f.fontDescriptor.symbolicTraits.contains(trait))
            return
        }
        let storage = tv.textStorage
        var allHave = true
        storage.enumerateAttribute(.font, in: r) { v, _, _ in
            if !((v as? UIFont) ?? base).fontDescriptor.symbolicTraits.contains(trait) { allHave = false }
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: r) { v, sub, _ in
            storage.addAttribute(.font, value: ((v as? UIFont) ?? base).with(trait, on: !allHave), range: sub)
        }
        storage.endEditing()
        changed(tv)
    }

    private func toggleAttribute(_ key: NSAttributedString.Key, on value: NSNumber) {
        guard let tv = textView else { return }
        let r = tv.selectedRange
        if r.length == 0 {
            if tv.typingAttributes[key] == nil { tv.typingAttributes[key] = value } else { tv.typingAttributes[key] = nil }
            return
        }
        var allHave = true
        tv.textStorage.enumerateAttribute(key, in: r) { v, _, _ in
            if (v as? NSNumber)?.doubleValue ?? 0 == 0 { allHave = false }
        }
        if allHave {
            tv.textStorage.removeAttribute(key, range: r)
        } else {
            tv.textStorage.addAttribute(key, value: value, range: r)
        }
        changed(tv)
    }

    private func changed(_ tv: UITextView) {
        tv.delegate?.textViewDidChange?(tv)
    }

    // MARK: - RTF 序列化

    nonisolated static func decode(_ data: Data?, fallback: String) -> NSAttributedString {
        if let data,
           let s = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                           documentAttributes: nil) {
            // RTF 不保存动态颜色，把黑色恢复为 label 颜色以支持深色模式
            let m = NSMutableAttributedString(attributedString: s)
            m.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: m.length)) { v, r, _ in
                if let c = v as? UIColor, c.isBlackish { m.addAttribute(.foregroundColor, value: UIColor.label, range: r) }
            }
            return m
        }
        return NSAttributedString(string: fallback, attributes: defaultAttributes)
    }

    nonisolated static func encode(_ text: NSAttributedString) -> Data? {
        guard text.length > 0 else { return nil }
        return try? text.data(from: NSRange(location: 0, length: text.length),
                              documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    nonisolated static var defaultAttributes: [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 5
        return [.font: baseFont, .foregroundColor: UIColor.label, .paragraphStyle: p]
    }
}

private extension UIFont {
    func with(_ trait: UIFontDescriptor.SymbolicTraits, on: Bool) -> UIFont {
        var traits = fontDescriptor.symbolicTraits
        if on { traits.insert(trait) } else { traits.remove(trait) }
        guard let d = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: d, size: pointSize)
    }
}

private extension UIColor {
    var isBlackish: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
        return r < 0.1 && g < 0.1 && b < 0.1
    }
}

/// 可随内容增高的富文本正文编辑器
struct RichTextEditor: UIViewRepresentable {
    @Binding var text: NSAttributedString
    let controller: RichTextController
    var placeholder: String
    var onFocus: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.allowsEditingTextAttributes = true
        tv.isFindInteractionEnabled = true
        tv.adjustsFontForContentSizeCategory = true
        tv.attributedText = text
        tv.typingAttributes = RichTextController.defaultAttributes
        tv.delegate = context.coordinator
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        controller.textView = tv
        context.coordinator.placeholder.text = placeholder
        context.coordinator.attachPlaceholder(to: tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        if !tv.attributedText.isEqual(to: text) && !context.coordinator.isEditing {
            tv.attributedText = text
        }
        context.coordinator.placeholder.isHidden = tv.textStorage.length > 0
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(size.height, 240))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditor
        var isEditing = false
        let placeholder = UILabel()

        init(_ parent: RichTextEditor) { self.parent = parent }

        func attachPlaceholder(to tv: UITextView) {
            placeholder.font = RichTextController.baseFont
            placeholder.textColor = .placeholderText
            placeholder.translatesAutoresizingMaskIntoConstraints = false
            tv.addSubview(placeholder)
            NSLayoutConstraint.activate([
                placeholder.leadingAnchor.constraint(equalTo: tv.leadingAnchor),
                placeholder.topAnchor.constraint(equalTo: tv.topAnchor),
            ])
            placeholder.isHidden = tv.textStorage.length > 0
        }

        func textViewDidChange(_ tv: UITextView) {
            placeholder.isHidden = tv.textStorage.length > 0
            isEditing = true
            parent.text = NSAttributedString(attributedString: tv.attributedText)
            DispatchQueue.main.async { self.isEditing = false }
            tv.invalidateIntrinsicContentSize()
        }

        func textViewDidBeginEditing(_ tv: UITextView) { parent.onFocus(true) }
        func textViewDidEndEditing(_ tv: UITextView) { parent.onFocus(false) }
    }
}

/// 「格式」面板
struct FormatPanel: View {
    let controller: RichTextController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("格式").font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.subheadline.bold()).foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
            }
            HStack(spacing: 8) {
                ForEach(RichTextController.Style.allCases) { s in
                    Button { controller.setStyle(s) } label: {
                        Text(s.name)
                            .font(s == .title ? .title3.bold() : s == .heading ? .headline : .body)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            HStack(spacing: 8) {
                group {
                    btn("bold") { controller.toggleBold() }
                    btn("italic") { controller.toggleItalic() }
                    btn("underline") { controller.toggleUnderline() }
                    btn("strikethrough") { controller.toggleStrikethrough() }
                }
                group {
                    btn("list.bullet") { controller.toggleBullets() }
                    btn("text.quote") { controller.toggleQuote() }
                }
            }
            HStack(spacing: 14) {
                ForEach(Array(RichTextController.textColors.enumerated()), id: \.offset) { _, c in
                    Button { controller.setColor(c) } label: {
                        Circle().fill(Color(uiColor: c)).frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Color.primary.opacity(0.15)))
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(20)
        .presentationDetents([.height(250)])
        .presentationBackgroundInteraction(.enabled)
        .presentationDragIndicator(.hidden)
    }

    private func group<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 0) { content() }
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
    }

    private func btn(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 40)
        }
    }
}
