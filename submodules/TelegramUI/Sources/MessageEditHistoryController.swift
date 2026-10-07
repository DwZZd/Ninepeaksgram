import Foundation
import UIKit
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext

final class MessageEditHistoryController: ViewController {
    private let presentationData: PresentationData
    private let message: Message
    private let textView = UITextView()

    init(context: AccountContext, message: Message) {
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.message = message
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationTheme: self.presentationData.theme, presentationStrings: self.presentationData.strings))
        self.title = "История изменений"
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
        self.textView.backgroundColor = .clear
        self.textView.isEditable = false
        self.textView.isSelectable = true
        self.textView.alwaysBounceVertical = true
        self.textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        self.textView.attributedText = self.historyText()
        self.displayNode.view.addSubview(self.textView)
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        transition.updateFrame(view: self.textView, frame: CGRect(x: layout.safeInsets.left, y: top, width: layout.size.width - layout.safeInsets.left - layout.safeInsets.right, height: max(0, layout.size.height - top - layout.safeInsets.bottom)))
    }

    private func historyText() -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        let theme = self.presentationData.theme
        func append(title: String, timestamp: Int32, text: String, entities: [MessageTextEntity], media: String?) {
            let date = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
            result.append(NSAttributedString(string: "\(title) · \(date)\n", attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: theme.list.itemAccentColor]))
            let body = NSMutableAttributedString(string: text.isEmpty ? (media == nil ? "Без текста" : "") : text, attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: theme.list.itemPrimaryTextColor])
            for entity in entities {
                let range = NSRange(location: entity.range.lowerBound, length: entity.range.count)
                guard range.location >= 0, range.length > 0, NSMaxRange(range) <= body.length else { continue }
                switch entity.type {
                case .Bold:
                    body.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 17), range: range)
                case .Italic:
                    body.addAttribute(.font, value: UIFont.italicSystemFont(ofSize: 17), range: range)
                case .Code, .Pre:
                    body.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular), range: range)
                case .Strikethrough:
                    body.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                case .Underline:
                    body.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                default:
                    break
                }
            }
            result.append(body)
            if let media = media {
                result.append(NSAttributedString(string: text.isEmpty ? media : "\n\(media)", attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: theme.list.itemSecondaryTextColor]))
            }
            result.append(NSAttributedString(string: "\n\n"))
        }
        append(title: "Текущая версия", timestamp: self.message.editedTime ?? self.message.timestamp, text: self.message.text, entities: self.message.textEntitiesAttribute?.entities ?? [], media: self.message.ninegramHistoryMediaDescription)
        for (index, version) in self.message.ninegramEditHistory.enumerated().reversed() {
            append(title: "Сохранённая версия \(index + 1)", timestamp: version.timestamp, text: version.text, entities: version.entities?.entities ?? [], media: version.mediaDescription)
        }
        return result
    }
}
