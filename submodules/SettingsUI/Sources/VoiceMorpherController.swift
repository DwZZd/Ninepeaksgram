import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// MARK: - Entry Definition

private enum VoiceMorpherSection: Int32 {
    case enable
    case presets
}

private enum VoiceMorpherEntry: ItemListNodeEntry {
    case enableHeader(PresentationTheme, String)
    case enableToggle(PresentationTheme, String, Bool)
    case enableInfo(PresentationTheme, String)
    case presetsHeader(PresentationTheme, String)
    case preset(PresentationTheme, Int, String, String, Bool) // id, name, description, selected
    
    var section: ItemListSectionId {
        switch self {
        case .enableHeader, .enableToggle, .enableInfo:
            return VoiceMorpherSection.enable.rawValue
        case .presetsHeader, .preset:
            return VoiceMorpherSection.presets.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
        case .enableHeader: return 0
        case .enableToggle: return 1
        case .enableInfo: return 2
        case .presetsHeader: return 3
        case let .preset(_, id, _, _, _): return 10 + Int32(id)
        }
    }
    
    static func ==(lhs: VoiceMorpherEntry, rhs: VoiceMorpherEntry) -> Bool {
        switch lhs {
        case let .enableHeader(lhsTheme, lhsText):
            if case let .enableHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            }
            return false
        case let .enableToggle(lhsTheme, lhsText, lhsValue):
            if case let .enableToggle(rhsTheme, rhsText, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .enableInfo(lhsTheme, lhsText):
            if case let .enableInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            }
            return false
        case let .presetsHeader(lhsTheme, lhsText):
            if case let .presetsHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            }
            return false
        case let .preset(lhsTheme, lhsId, lhsName, lhsDesc, lhsSelected):
            if case let .preset(rhsTheme, rhsId, rhsName, rhsDesc, rhsSelected) = rhs,
               lhsTheme === rhsTheme, lhsId == rhsId, lhsName == rhsName, lhsDesc == rhsDesc, lhsSelected == rhsSelected {
                return true
            }
            return false
        }
    }
    
    static func <(lhs: VoiceMorpherEntry, rhs: VoiceMorpherEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! VoiceMorpherControllerArguments
        switch self {
        case let .enableHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .enableToggle(_, text, value):
            return ItemListSwitchItem(presentationData: presentationData, title: text, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleEnabled(value)
            })
        case let .enableInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .presetsHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .preset(_, id, name, _, selected):
            return ItemListCheckboxItem(presentationData: presentationData, title: name, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectPreset(id)
            })
        }
    }
}

// MARK: - Arguments

private final class VoiceMorpherControllerArguments {
    let toggleEnabled: (Bool) -> Void
    let selectPreset: (Int) -> Void
    
    init(
        toggleEnabled: @escaping (Bool) -> Void,
        selectPreset: @escaping (Int) -> Void
    ) {
        self.toggleEnabled = toggleEnabled
        self.selectPreset = selectPreset
    }
}

// MARK: - State

private struct VoiceMorpherControllerState: Equatable {
    var isEnabled: Bool
    var selectedPresetId: Int
}

// MARK: - Entries Builder

private func voiceMorpherControllerEntries(presentationData: PresentationData, state: VoiceMorpherControllerState) -> [VoiceMorpherEntry] {
    var entries: [VoiceMorpherEntry] = []
    
    let theme = presentationData.theme
    
    entries.append(.enableHeader(theme, "ИЗМЕНЕНИЕ ГОЛОСА"))
    entries.append(.enableToggle(theme, "Включить Voice Morpher", state.isEnabled))
    entries.append(.enableInfo(theme, "Изменяет твой голос при записи голосовых сообщений. Использует встроенные аудио-эффекты iOS."))
    
    entries.append(.presetsHeader(theme, "ВЫБЕРИТЕ ЭФФЕКТ"))
    
    // Add all presets except disabled (it's controlled by toggle)
    for preset in VoiceMorpherManager.VoicePreset.allCases where preset != .disabled {
        let isSelected = preset.rawValue == state.selectedPresetId
        entries.append(.preset(theme, preset.rawValue, preset.name, preset.description, isSelected))
    }
    
    return entries
}

// MARK: - Controller

public func voiceMorpherController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(
        VoiceMorpherControllerState(
            isEnabled: VoiceMorpherManager.shared.isEnabled,
            selectedPresetId: VoiceMorpherManager.shared.selectedPresetId == 0 ? 1 : VoiceMorpherManager.shared.selectedPresetId
        ),
        ignoreRepeated: true
    )
    let stateValue = Atomic(value: VoiceMorpherControllerState(
        isEnabled: VoiceMorpherManager.shared.isEnabled,
        selectedPresetId: VoiceMorpherManager.shared.selectedPresetId == 0 ? 1 : VoiceMorpherManager.shared.selectedPresetId
    ))
    
    let updateState: ((inout VoiceMorpherControllerState) -> Void) -> Void = { f in
        let result = stateValue.modify { state in
            var state = state
            f(&state)
            return state
        }
        statePromise.set(result)
    }
    
    let arguments = VoiceMorpherControllerArguments(
        toggleEnabled: { value in
            VoiceMorpherManager.shared.isEnabled = value
            updateState { state in
                state.isEnabled = value
            }
        },
        selectPreset: { id in
            VoiceMorpherManager.shared.selectedPresetId = id
            updateState { state in
                state.selectedPresetId = id
            }
        }
    )
    
    let signal = combineLatest(
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries = voiceMorpherControllerEntries(presentationData: presentationData, state: state)
        
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Голосовой двойник"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        
        return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal)
    return controller
}
