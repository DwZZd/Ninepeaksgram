import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// MARK: - Entry Definition

private enum GhostModeSection: Int32 {
    case master
    case features
}

private enum GhostModeEntry: ItemListNodeEntry {
    case masterHeader(PresentationTheme, String)
    case masterToggle(PresentationTheme, String, Bool, Int, Int) // title, isOn, activeCount, totalCount
    case masterInfo(PresentationTheme, String)
    case featuresHeader(PresentationTheme, String)
    case hideReadReceipts(PresentationTheme, String, Bool)
    case hideStoryViews(PresentationTheme, String, Bool)
    case hideOnlineStatus(PresentationTheme, String, Bool)
    case hideTypingIndicator(PresentationTheme, String, Bool)
    case forceOffline(PresentationTheme, String, Bool)
    
    var section: ItemListSectionId {
        switch self {
        case .masterHeader, .masterToggle, .masterInfo:
            return GhostModeSection.master.rawValue
        case .featuresHeader, .hideReadReceipts, .hideStoryViews, .hideOnlineStatus, .hideTypingIndicator, .forceOffline:
            return GhostModeSection.features.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
        case .masterHeader: return 0
        case .masterToggle: return 1
        case .masterInfo: return 2
        case .featuresHeader: return 3
        case .hideReadReceipts: return 4
        case .hideStoryViews: return 5
        case .hideOnlineStatus: return 6
        case .hideTypingIndicator: return 7
        case .forceOffline: return 8
        }
    }
    
    static func ==(lhs: GhostModeEntry, rhs: GhostModeEntry) -> Bool {
        switch lhs {
        case let .masterHeader(lhsTheme, lhsText):
            if case let .masterHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            }
            return false
        case let .masterToggle(lhsTheme, lhsText, lhsValue, lhsActive, lhsTotal):
            if case let .masterToggle(rhsTheme, rhsText, rhsValue, rhsActive, rhsTotal) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue, lhsActive == rhsActive, lhsTotal == rhsTotal {
                return true
            }
            return false
        case let .masterInfo(lhsTheme, lhsText):
            if case let .masterInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            }
            return false
        case let .featuresHeader(lhsTheme, lhsText):
            if case let .featuresHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            }
            return false
        case let .hideReadReceipts(lhsTheme, lhsText, lhsValue):
            if case let .hideReadReceipts(rhsTheme, rhsText, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .hideStoryViews(lhsTheme, lhsText, lhsValue):
            if case let .hideStoryViews(rhsTheme, rhsText, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .hideOnlineStatus(lhsTheme, lhsText, lhsValue):
            if case let .hideOnlineStatus(rhsTheme, rhsText, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .hideTypingIndicator(lhsTheme, lhsText, lhsValue):
            if case let .hideTypingIndicator(rhsTheme, rhsText, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .forceOffline(lhsTheme, lhsText, lhsValue):
            if case let .forceOffline(rhsTheme, rhsText, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        }
    }
    
    static func <(lhs: GhostModeEntry, rhs: GhostModeEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! GhostModeControllerArguments
        switch self {
        case let .masterHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .masterToggle(_, text, value, activeCount, totalCount):
            let title = "\(text) \(activeCount)/\(totalCount)"
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleMaster(value)
            })
        case let .masterInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .featuresHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .hideReadReceipts(_, text, value):
            return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggleHideReadReceipts()
            })
        case let .hideStoryViews(_, text, value):
            return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggleHideStoryViews()
            })
        case let .hideOnlineStatus(_, text, value):
            return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggleHideOnlineStatus()
            })
        case let .hideTypingIndicator(_, text, value):
            return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggleHideTypingIndicator()
            })
        case let .forceOffline(_, text, value):
            return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggleForceOffline()
            })
        }
    }
}

// MARK: - Arguments

private final class GhostModeControllerArguments {
    let toggleMaster: (Bool) -> Void
    let toggleHideReadReceipts: () -> Void
    let toggleHideStoryViews: () -> Void
    let toggleHideOnlineStatus: () -> Void
    let toggleHideTypingIndicator: () -> Void
    let toggleForceOffline: () -> Void
    
    init(
        toggleMaster: @escaping (Bool) -> Void,
        toggleHideReadReceipts: @escaping () -> Void,
        toggleHideStoryViews: @escaping () -> Void,
        toggleHideOnlineStatus: @escaping () -> Void,
        toggleHideTypingIndicator: @escaping () -> Void,
        toggleForceOffline: @escaping () -> Void
    ) {
        self.toggleMaster = toggleMaster
        self.toggleHideReadReceipts = toggleHideReadReceipts
        self.toggleHideStoryViews = toggleHideStoryViews
        self.toggleHideOnlineStatus = toggleHideOnlineStatus
        self.toggleHideTypingIndicator = toggleHideTypingIndicator
        self.toggleForceOffline = toggleForceOffline
    }
}

// MARK: - State

private struct GhostModeControllerState: Equatable {
    var isEnabled: Bool
    var hideReadReceipts: Bool
    var hideStoryViews: Bool
    var hideOnlineStatus: Bool
    var hideTypingIndicator: Bool
    var forceOffline: Bool
    
    static func ==(lhs: GhostModeControllerState, rhs: GhostModeControllerState) -> Bool {
        return lhs.isEnabled == rhs.isEnabled &&
               lhs.hideReadReceipts == rhs.hideReadReceipts &&
               lhs.hideStoryViews == rhs.hideStoryViews &&
               lhs.hideOnlineStatus == rhs.hideOnlineStatus &&
               lhs.hideTypingIndicator == rhs.hideTypingIndicator &&
               lhs.forceOffline == rhs.forceOffline
    }
}

// MARK: - Entries Builder

private func ghostModeControllerEntries(presentationData: PresentationData, state: GhostModeControllerState) -> [GhostModeEntry] {
    var entries: [GhostModeEntry] = []
    
    let theme = presentationData.theme
    
    // Count active features
    var activeCount = 0
    if state.hideReadReceipts { activeCount += 1 }
    if state.hideStoryViews { activeCount += 1 }
    if state.hideOnlineStatus { activeCount += 1 }
    if state.hideTypingIndicator { activeCount += 1 }
    if state.forceOffline { activeCount += 1 }
    
    // Master section
    entries.append(.masterHeader(theme, "РЕЖИМ ПРИЗРАКА"))
    entries.append(.masterToggle(theme, "Режим призрака", state.isEnabled, activeCount, 5))
    entries.append(.masterInfo(theme, "Когда включен, выбранные функции приватности будут активны."))
    
    // Features section
    entries.append(.featuresHeader(theme, "ФУНКЦИИ"))
    entries.append(.hideReadReceipts(theme, "Не читать сообщения", state.hideReadReceipts))
    entries.append(.hideStoryViews(theme, "Не читать истории", state.hideStoryViews))
    entries.append(.hideOnlineStatus(theme, "Не отправлять «онлайн»", state.hideOnlineStatus))
    entries.append(.hideTypingIndicator(theme, "Не отправлять «печатает»", state.hideTypingIndicator))
    entries.append(.forceOffline(theme, "Автоматический «офлайн»", state.forceOffline))
    
    return entries
}

// MARK: - Controller

public func ghostModeController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(
        GhostModeControllerState(
            isEnabled: GhostModeManager.shared.isEnabled,
            hideReadReceipts: GhostModeManager.shared.hideReadReceipts,
            hideStoryViews: GhostModeManager.shared.hideStoryViews,
            hideOnlineStatus: GhostModeManager.shared.hideOnlineStatus,
            hideTypingIndicator: GhostModeManager.shared.hideTypingIndicator,
            forceOffline: GhostModeManager.shared.forceOffline
        ),
        ignoreRepeated: true
    )
    let stateValue = Atomic(value: GhostModeControllerState(
        isEnabled: GhostModeManager.shared.isEnabled,
        hideReadReceipts: GhostModeManager.shared.hideReadReceipts,
        hideStoryViews: GhostModeManager.shared.hideStoryViews,
        hideOnlineStatus: GhostModeManager.shared.hideOnlineStatus,
        hideTypingIndicator: GhostModeManager.shared.hideTypingIndicator,
        forceOffline: GhostModeManager.shared.forceOffline
    ))
    
    let updateState: ((inout GhostModeControllerState) -> Void) -> Void = { f in
        let result = stateValue.modify { state in
            var state = state
            f(&state)
            return state
        }
        statePromise.set(result)
    }
    
    let arguments = GhostModeControllerArguments(
        toggleMaster: { value in
            GhostModeManager.shared.isEnabled = value
            updateState { state in
                state.isEnabled = value
            }
        },
        toggleHideReadReceipts: {
            let newValue = !GhostModeManager.shared.hideReadReceipts
            GhostModeManager.shared.hideReadReceipts = newValue
            updateState { state in
                state.hideReadReceipts = newValue
            }
        },
        toggleHideStoryViews: {
            let newValue = !GhostModeManager.shared.hideStoryViews
            GhostModeManager.shared.hideStoryViews = newValue
            updateState { state in
                state.hideStoryViews = newValue
            }
        },
        toggleHideOnlineStatus: {
            let newValue = !GhostModeManager.shared.hideOnlineStatus
            GhostModeManager.shared.hideOnlineStatus = newValue
            updateState { state in
                state.hideOnlineStatus = newValue
            }
        },
        toggleHideTypingIndicator: {
            let newValue = !GhostModeManager.shared.hideTypingIndicator
            GhostModeManager.shared.hideTypingIndicator = newValue
            updateState { state in
                state.hideTypingIndicator = newValue
            }
        },
        toggleForceOffline: {
            let newValue = !GhostModeManager.shared.forceOffline
            GhostModeManager.shared.forceOffline = newValue
            updateState { state in
                state.forceOffline = newValue
            }
        }
    )
    
    // Refresh UI when Always Online is enabled externally and auto-disables Ghost Mode —
    // the isEnabled flip happens in GhostModeManager from MiscSettingsManager context,
    // so we need to pull fresh values from the manager.
    let miscSettingsChangedSignal: Signal<Void, NoError> = Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(
            forName: MiscSettingsManager.settingsChangedNotification,
            object: nil,
            queue: .main
        ) { _ in
            updateState { state in
                state.isEnabled          = GhostModeManager.shared.isEnabled
                state.hideReadReceipts   = GhostModeManager.shared.hideReadReceipts
                state.hideStoryViews     = GhostModeManager.shared.hideStoryViews
                state.hideOnlineStatus   = GhostModeManager.shared.hideOnlineStatus
                state.hideTypingIndicator = GhostModeManager.shared.hideTypingIndicator
                state.forceOffline       = GhostModeManager.shared.forceOffline
            }
        }
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    }
    let _ = miscSettingsChangedSignal.start()
    
    let signal = combineLatest(
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries = ghostModeControllerEntries(presentationData: presentationData, state: state)
        
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Режим призрака"),
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
    
    let controller = ItemListController(context: context, state: signal)
    return controller
}
