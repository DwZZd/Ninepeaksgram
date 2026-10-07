import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// MARK: - Section / Entry definitions

private enum SendDelaySection: Int32 {
    case main
}

private enum SendDelayEntry: ItemListNodeEntry {
    case toggle(PresentationTheme, String, Bool)
    case info(PresentationTheme, String)

    var section: ItemListSectionId {
        return SendDelaySection.main.rawValue
    }

    var stableId: Int32 {
        switch self {
        case .toggle: return 0
        case .info:   return 1
        }
    }

    static func ==(lhs: SendDelayEntry, rhs: SendDelayEntry) -> Bool {
        switch lhs {
        case let .toggle(lhsTheme, lhsText, lhsValue):
            if case let .toggle(rhsTheme, rhsText, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .info(lhsTheme, lhsText):
            if case let .info(rhsTheme, rhsText) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            }
            return false
        }
    }

    static func <(lhs: SendDelayEntry, rhs: SendDelayEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SendDelayControllerArguments
        switch self {
        case let .toggle(_, text, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: text,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    arguments.toggleEnabled(newValue)
                }
            )
        case let .info(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

// MARK: - Arguments

private final class SendDelayControllerArguments {
    let toggleEnabled: (Bool) -> Void
    init(toggleEnabled: @escaping (Bool) -> Void) {
        self.toggleEnabled = toggleEnabled
    }
}

// MARK: - State

private struct SendDelayControllerState: Equatable {
    var isEnabled: Bool
}

// MARK: - Entries builder

private func sendDelayControllerEntries(
    presentationData: PresentationData,
    state: SendDelayControllerState
) -> [SendDelayEntry] {
    let theme = presentationData.theme
    return [
        .toggle(theme, "Использовать отложку", state.isEnabled),
        .info(theme, "Автоматически ставит задержку в ~12 секунд (дольше для сообщений с вложениями) при отправке сообщений. При использовании этой функции вы не будете появляться в сети.")
    ]
}

// MARK: - Controller

public func sendDelayController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(
        SendDelayControllerState(isEnabled: SendDelayManager.shared.isEnabled),
        ignoreRepeated: true
    )
    let stateValue = Atomic(value: SendDelayControllerState(isEnabled: SendDelayManager.shared.isEnabled))

    let updateState: ((inout SendDelayControllerState) -> Void) -> Void = { f in
        let result = stateValue.modify { state in
            var s = state; f(&s); return s
        }
        statePromise.set(result)
    }

    let arguments = SendDelayControllerArguments(
        toggleEnabled: { value in
            SendDelayManager.shared.isEnabled = value
            updateState { $0.isEnabled = value }
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries = sendDelayControllerEntries(presentationData: presentationData, state: state)

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Отложка сообщений"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
