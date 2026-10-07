import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// MARK: - Entry Definition

private enum GhostgramSettingsSection: Int32 {
    case features
}

private enum GhostgramSettingsEntry: ItemListNodeEntry {
    case deletedMessages(PresentationTheme, String, String)
    case ghostMode(PresentationTheme, String, String)
    case misc(PresentationTheme, String, String)
    case voiceMorpher(PresentationTheme, String, String)
    case sendDelay(PresentationTheme, String, String)
    case info(PresentationTheme, String)
    
    var section: ItemListSectionId {
        return GhostgramSettingsSection.features.rawValue
    }
    
    var stableId: Int32 {
        switch self {
        case .deletedMessages:
            return 0
        case .ghostMode:
            return 1
        case .misc:
            return 2
        case .voiceMorpher:
            return 3
        case .sendDelay:
            return 4
        case .info:
            return 5
        }
    }
    
    static func ==(lhs: GhostgramSettingsEntry, rhs: GhostgramSettingsEntry) -> Bool {
        switch lhs {
        case let .deletedMessages(lhsTheme, lhsText, lhsValue):
            if case let .deletedMessages(rhsTheme, rhsText, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .ghostMode(lhsTheme, lhsText, lhsValue):
            if case let .ghostMode(rhsTheme, rhsText, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .misc(lhsTheme, lhsText, lhsValue):
            if case let .misc(rhsTheme, rhsText, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .voiceMorpher(lhsTheme, lhsText, lhsValue):
            if case let .voiceMorpher(rhsTheme, rhsText, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .sendDelay(lhsTheme, lhsText, lhsValue):
            if case let .sendDelay(rhsTheme, rhsText, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .info(lhsTheme, lhsText):
            if case let .info(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            }
            return false
        }
    }
    
    static func <(lhs: GhostgramSettingsEntry, rhs: GhostgramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! GhostgramSettingsControllerArguments
        switch self {
        case let .deletedMessages(_, text, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: text,
                label: value,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openDeletedMessages()
                }
            )
        case let .ghostMode(_, text, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: text,
                label: value,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openGhostMode()
                }
            )
        case let .misc(_, text, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: text,
                label: value,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openMisc()
                }
            )
        case let .voiceMorpher(_, text, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: text,
                label: value,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openVoiceMorpher()
                }
            )
        case let .sendDelay(_, text, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: text,
                label: value,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openSendDelay()
                }
            )
        case let .info(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

// MARK: - Arguments

private final class GhostgramSettingsControllerArguments {
    let openDeletedMessages: () -> Void
    let openGhostMode: () -> Void
    let openMisc: () -> Void
    let openVoiceMorpher: () -> Void
    let openSendDelay: () -> Void
    
    init(
        openDeletedMessages: @escaping () -> Void,
        openGhostMode: @escaping () -> Void,
        openMisc: @escaping () -> Void,
        openVoiceMorpher: @escaping () -> Void,
        openSendDelay: @escaping () -> Void
    ) {
        self.openDeletedMessages = openDeletedMessages
        self.openGhostMode = openGhostMode
        self.openMisc = openMisc
        self.openVoiceMorpher = openVoiceMorpher
        self.openSendDelay = openSendDelay
    }
}

// MARK: - State

private struct GhostgramSettingsState: Equatable {
    var deletedMessagesEnabled: Bool
    var ghostModeEnabled: Bool
    var ghostModeActiveCount: Int
    var miscEnabled: Bool
    var miscActiveCount: Int
    var voiceMorpherEnabled: Bool
    var voiceMorpherPresetName: String
    var sendDelayEnabled: Bool
    
    static func current() -> GhostgramSettingsState {
        return GhostgramSettingsState(
            deletedMessagesEnabled: AntiDeleteManager.shared.isEnabled,
            ghostModeEnabled: GhostModeManager.shared.isEnabled,
            ghostModeActiveCount: GhostModeManager.shared.activeFeatureCount,
            miscEnabled: MiscSettingsManager.shared.isEnabled,
            miscActiveCount: MiscSettingsManager.shared.activeFeatureCount,
            voiceMorpherEnabled: VoiceMorpherManager.shared.isEnabled,
            voiceMorpherPresetName: VoiceMorpherManager.shared.selectedPreset.name,
            sendDelayEnabled: SendDelayManager.shared.isEnabled
        )
    }
}

// MARK: - Entries builder

private func ghostgramSettingsControllerEntries(
    presentationData: PresentationData,
    state: GhostgramSettingsState
) -> [GhostgramSettingsEntry] {
    var entries: [GhostgramSettingsEntry] = []
    
    // Deleted Messages
    let deletedStatus = state.deletedMessagesEnabled ? "Вкл" : "Выкл"
    entries.append(.deletedMessages(presentationData.theme, "Удалённые сообщения", deletedStatus))
    
    // Ghost Mode
    let ghostModeStatus = state.ghostModeEnabled ? "\(state.ghostModeActiveCount)/5" : "Выкл"
    entries.append(.ghostMode(presentationData.theme, "Режим призрака", ghostModeStatus))
    
    // Misc
    let miscStatus = state.miscEnabled ? "\(state.miscActiveCount)/5" : "Выкл"
    entries.append(.misc(presentationData.theme, "Прочее", miscStatus))
    

    // Voice Morpher
    let voiceMorpherStatus = state.voiceMorpherEnabled ? state.voiceMorpherPresetName : "Выкл"
    entries.append(.voiceMorpher(presentationData.theme, "Голосовой двойник", voiceMorpherStatus))
    
    // Send Delay
    let sendDelayStatus = state.sendDelayEnabled ? "Вкл" : "Выкл"
    entries.append(.sendDelay(presentationData.theme, "Отложка сообщений", sendDelayStatus))
    
    // Info
    entries.append(.info(presentationData.theme, "Функции конфиденциальности Ninegram. Скрытые отметки о прочтении, обход исчезающих сообщений, обход защиты от пересылки и другое."))
    
    return entries
}

// MARK: - Controller

public func ghostgramSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController, Bool) -> Void)?
    
    let stateValue = Atomic(value: GhostgramSettingsState.current())
    let statePromise = ValuePromise(GhostgramSettingsState.current(), ignoreRepeated: true)
    
    let arguments = GhostgramSettingsControllerArguments(
        openDeletedMessages: {
            pushControllerImpl?(deletedMessagesController(context: context), true)
        },
        openGhostMode: {
            pushControllerImpl?(ghostModeController(context: context), true)
        },
        openMisc: {
            pushControllerImpl?(miscController(context: context), true)
        },

        openVoiceMorpher: {
            pushControllerImpl?(voiceMorpherController(context: context), true)
        },
        openSendDelay: {
            pushControllerImpl?(sendDelayController(context: context), true)
        }
    )
    
    let signal = combineLatest(
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries = ghostgramSettingsControllerEntries(presentationData: presentationData, state: state)
        
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Ninegram"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: true
        )
        
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: true
        )
        
        return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal)
    
    // Refresh state when view appears
    controller.visibleBottomContentOffsetChanged = { _ in }
    controller.didAppear = { _ in
        let newState = GhostgramSettingsState.current()
        let _ = stateValue.modify { _ in newState }
        statePromise.set(newState)
    }
    
    pushControllerImpl = { [weak controller] c, animated in
        controller?.push(c)
    }
    return controller
}
