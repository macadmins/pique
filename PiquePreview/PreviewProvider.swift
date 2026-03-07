import Cocoa
import QuickLookUI
import UniformTypeIdentifiers
import OSLog

@objc(PreviewProvider)
class PreviewProvider: NSViewController, QLPreviewingController {
    private let logger = Logger(subsystem: "com.pique.app", category: "preview")

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        scrollView.documentView = textView
        view = scrollView
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let text = try FileReader.read(url: url)
            let format = FileFormat(pathExtension: url.pathExtension) ?? .json
            let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let html = SyntaxHighlighter.highlight(text, format: format, darkMode: isDark)

            logger.info("Preview for \(url.lastPathComponent, privacy: .public)")

            guard let htmlData = html.data(using: .utf8),
                  let attrString = NSAttributedString(
                      html: htmlData,
                      documentAttributes: nil
                  ) else {
                handler(nil)
                return
            }

            if let scrollView = view as? NSScrollView,
               let textView = scrollView.documentView as? NSTextView {
                textView.textStorage?.setAttributedString(attrString)
                let bg: NSColor = isDark ? NSColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1) : .white
                textView.backgroundColor = bg
                scrollView.backgroundColor = bg
            }

            handler(nil)
        } catch {
            logger.error("Preview failed: \(error.localizedDescription, privacy: .public)")
            handler(error)
        }
    }
}
