import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// MARK: - Entry Definition

private enum MiscSection: Int32 {
    case master
    case features
}

private enum MiscEntry: ItemListNodeEntry {
    case masterHeader(PresentationTheme, String)
    case masterToggle(PresentationTheme, String, Bool, Int, Int)
    case masterInfo(PresentationTheme, String)
    case featuresHeader(PresentationTheme, String)
    case bypassCopyProtection(PresentationTheme, String, Bool)
    case disableViewOnceAutoDelete(PresentationTheme, String, Bool)
    case bypassScreenshotProtection(PresentationTheme, String, Bool)
    case blockAds(PresentationTheme, String, Bool)
    case alwaysOnline(PresentationTheme, String, Bool)
    
    var section: ItemListSectionId {
        switch self {
        case .masterHeader, .masterToggle, .masterInfo:
            return MiscSection.master.rawValue
        case .featuresHeader, .bypassCopyProtection, .disableViewOnceAutoDelete, .bypassScreenshotProtection, .blockAds, .alwaysOnline:
            return MiscSection.features.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
        case .masterHeader: return 0
        case .masterToggle: return 1
        case .masterInfo: return 2
        case .featuresHeader: return 3
        case .bypassCopyProtection: return 4
        case .disableViewOnceAutoDelete: return 5
        case .bypassScreenshotProtection: return 6
        case .blockAds: return 7
        case .alwaysOnline: return 8
        }
    }
    
    static func ==(lhs: MiscEntry, rhs: MiscEntry) -> Bool {
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
        case let .bypassCopyProtection(lhsTheme, lhsText, lhsValue):
            if case let .bypassCopyProtection(rhsTheme, rhsText, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .disableViewOnceAutoDelete(lhsTheme, lhsText, lhsValue):
            if case let .disableViewOnceAutoDelete(rhsTheme, rhsText, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .bypassScreenshotProtection(lhsTheme, lhsText, lhsValue):
            if case let .bypassScreenshotProtection(rhsTheme, rhsText, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .blockAds(lhsTheme, lhsText, lhsValue):
            if case let .blockAds(rhsTheme, rhsText, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .alwaysOnline(lhsTheme, lhsText, lhsValue):
            if case let .alwaysOnline(rhsTheme, rhsText, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        }
    }
    
    static func <(lhs: MiscEntry, rhs: MiscEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MiscControllerArguments
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
        case let .bypassCopyProtection(_, text, value):
            return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggleBypassCopyProtection()
            })
        case let .disableViewOnceAutoDelete(_, text, value):
            return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggleDisableViewOnceAutoDelete()
            })
        case let .bypassScreenshotProtection(_, text, value):
            return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggleBypassScreenshotProtection()
            })
        case let .blockAds(_, text, value):
            return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggleBlockAds()
            })
        case let .alwaysOnline(_, text, value):
            return ItemListCheckboxItem(presentationData: presentationData, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggleAlwaysOnline()
            })
        }
    }
}

// MARK: - Arguments

private final class MiscControllerArguments {
    let toggleMaster: (Bool) -> Void
    let toggleBypassCopyProtection: () -> Void
    let toggleDisableViewOnceAutoDelete: () -> Void
    let toggleBypassScreenshotProtection: () -> Void
    let toggleBlockAds: () -> Void
    let toggleAlwaysOnline: () -> Void
    
    init(
        toggleMaster: @escaping (Bool) -> Void,
        toggleBypassCopyProtection: @escaping () -> Void,
        toggleDisableViewOnceAutoDelete: @escaping () -> Void,
        toggleBypassScreenshotProtection: @escaping () -> Void,
        toggleBlockAds: @escaping () -> Void,
        toggleAlwaysOnline: @escaping () -> Void
    ) {
        self.toggleMaster = toggleMaster
        self.toggleBypassCopyProtection = toggleBypassCopyProtection
        self.toggleDisableViewOnceAutoDelete = toggleDisableViewOnceAutoDelete
        self.toggleBypassScreenshotProtection = toggleBypassScreenshotProtection
        self.toggleBlockAds = toggleBlockAds
        self.toggleAlwaysOnline = toggleAlwaysOnline
    }
}

// MARK: - State

private struct MiscControllerState: Equatable {
    var isEnabled: Bool
    var bypassCopyProtection: Bool
    var disableViewOnceAutoDelete: Bool
    var bypassScreenshotProtection: Bool
    var blockAds: Bool
    var alwaysOnline: Bool
    
    static func ==(lhs: MiscControllerState, rhs: MiscControllerState) -> Bool {
        return lhs.isEnabled == rhs.isEnabled &&
               lhs.bypassCopyProtection == rhs.bypassCopyProtection &&
               lhs.disableViewOnceAutoDelete == rhs.disableViewOnceAutoDelete &&
               lhs.bypassScreenshotProtection == rhs.bypassScreenshotProtection &&
               lhs.blockAds == rhs.blockAds &&
               lhs.alwaysOnline == rhs.alwaysOnline
    }
}

// MARK: - Entries Builder

private func miscControllerEntries(presentationData: PresentationData, state: MiscControllerState) -> [MiscEntry] {
    var entries: [MiscEntry] = []
    
    let theme = presentationData.theme
    
    var activeCount = 0
    if state.bypassCopyProtection { activeCount += 1 }
    if state.disableViewOnceAutoDelete { activeCount += 1 }
    if state.bypassScreenshotProtection { activeCount += 1 }
    if state.blockAds { activeCount += 1 }
    if state.alwaysOnline { activeCount += 1 }
    
    entries.append(.masterHeader(theme, "РАСШИРЕННЫЕ ВОЗМОЖНОСТИ"))
    entries.append(.masterToggle(theme, "Misc", state.isEnabled, activeCount, 5))
    entries.append(.masterInfo(theme, "Когда включено, выбранные функции обхода ограничений будут активны."))
    
    entries.append(.featuresHeader(theme, "ФУНКЦИИ"))
    entries.append(.bypassCopyProtection(theme, "Разрешить пересылку", state.bypassCopyProtection))
    entries.append(.disableViewOnceAutoDelete(theme, "Сохранять View Once", state.disableViewOnceAutoDelete))
    entries.append(.bypassScreenshotProtection(theme, "Разрешить скриншоты", state.bypassScreenshotProtection))
    entries.append(.blockAds(theme, "Блокировать рекламу", state.blockAds))
    entries.append(.alwaysOnline(theme, "Вечный онлайн", state.alwaysOnline))
    
    return entries
}

// MARK: - Controller

public func miscController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(
        MiscControllerState(
            isEnabled: MiscSettingsManager.shared.isEnabled,
            bypassCopyProtection: MiscSettingsManager.shared.bypassCopyProtection,
            disableViewOnceAutoDelete: MiscSettingsManager.shared.disableViewOnceAutoDelete,
            bypassScreenshotProtection: MiscSettingsManager.shared.bypassScreenshotProtection,
            blockAds: MiscSettingsManager.shared.blockAds,
            alwaysOnline: MiscSettingsManager.shared.alwaysOnline
        ),
        ignoreRepeated: true
    )
    let stateValue = Atomic(value: MiscControllerState(
        isEnabled: MiscSettingsManager.shared.isEnabled,
        bypassCopyProtection: MiscSettingsManager.shared.bypassCopyProtection,
        disableViewOnceAutoDelete: MiscSettingsManager.shared.disableViewOnceAutoDelete,
        bypassScreenshotProtection: MiscSettingsManager.shared.bypassScreenshotProtection,
        blockAds: MiscSettingsManager.shared.blockAds,
        alwaysOnline: MiscSettingsManager.shared.alwaysOnline
    ))
    
    let updateState: ((inout MiscControllerState) -> Void) -> Void = { f in
        let result = stateValue.modify { state in
            var state = state
            f(&state)
            return state
        }
        statePromise.set(result)
    }
    
    let arguments = MiscControllerArguments(
        toggleMaster: { value in
            MiscSettingsManager.shared.isEnabled = value
            updateState { state in
                state.isEnabled = value
            }
        },
        toggleBypassCopyProtection: {
            let newValue = !MiscSettingsManager.shared.bypassCopyProtection
            MiscSettingsManager.shared.bypassCopyProtection = newValue
            updateState { state in
                state.bypassCopyProtection = newValue
            }
        },
        toggleDisableViewOnceAutoDelete: {
            let newValue = !MiscSettingsManager.shared.disableViewOnceAutoDelete
            MiscSettingsManager.shared.disableViewOnceAutoDelete = newValue
            updateState { state in
                state.disableViewOnceAutoDelete = newValue
            }
        },
        toggleBypassScreenshotProtection: {
            let newValue = !MiscSettingsManager.shared.bypassScreenshotProtection
            MiscSettingsManager.shared.bypassScreenshotProtection = newValue
            updateState { state in
                state.bypassScreenshotProtection = newValue
            }
        },
        toggleBlockAds: {
            let newValue = !MiscSettingsManager.shared.blockAds
            MiscSettingsManager.shared.blockAds = newValue
            updateState { state in
                state.blockAds = newValue
            }
        },
        toggleAlwaysOnline: {
            let newValue = !MiscSettingsManager.shared.alwaysOnline
            MiscSettingsManager.shared.alwaysOnline = newValue
            // State will be refreshed via notification if Ghost Mode got auto-disabled
            updateState { state in
                state.alwaysOnline = newValue
            }
        }
    )
    
    // Refresh UI when Ghost Mode is auto-disabled by mutual exclusion —
    // the toggle flip happens externally, so we must pull fresh values from the managers.
    let ghostModeChangedSignal: Signal<Void, NoError> = Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(
            forName: GhostModeManager.settingsChangedNotification,
            object: nil,
            queue: .main
        ) { _ in
            updateState { state in
                state.isEnabled                  = MiscSettingsManager.shared.isEnabled
                state.bypassCopyProtection       = MiscSettingsManager.shared.bypassCopyProtection
                state.disableViewOnceAutoDelete  = MiscSettingsManager.shared.disableViewOnceAutoDelete
                state.bypassScreenshotProtection = MiscSettingsManager.shared.bypassScreenshotProtection
                state.blockAds                   = MiscSettingsManager.shared.blockAds
                state.alwaysOnline               = MiscSettingsManager.shared.alwaysOnline
            }
        }
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    }
    let _ = ghostModeChangedSignal.start()
    
    let signal = combineLatest(
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries = miscControllerEntries(presentationData: presentationData, state: state)
        
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Прочее"),
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
