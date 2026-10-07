import UIKit
import Postbox
import TelegramCore
import TelegramPresentationData
import SwiftSignalKit
import Display
import ContextUI
import AccountContext

func ninegramBurnAction(context: AccountContext, message: Message, onBurn: @escaping () -> Void = {}) -> ContextMenuActionItem {
    let actionId = "ninegram.burn"
    let icon: (PresentationTheme) -> UIImage? = { theme in
        generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.contextMenu.primaryColor)
    }
    let handler: ((ContextMenuActionItem.Action) -> Void)?
    if message.ninegramMediaBurned {
        handler = nil
    } else {
        handler = { action in
            onBurn()
            let disabled: ((ContextMenuActionItem.Action) -> Void)? = nil
            // Updating replaces the action node in the current context menu.
            // Its callback holds that node weakly: update only once, after the
            // transaction, or a second update would target a released node.
            let _ = (context.engine.messages.burnEphemeralMediaForSender(messageId: message.id)
            |> mapToSignal { _ -> Signal<Bool, NoError> in
                return context.account.postbox.transaction { transaction -> Bool in
                    return transaction.getMessage(message.id)?.ninegramMediaBurned ?? false
                }
            }
            |> deliverOnMainQueue).startStandalone(next: { burned in
                if burned {
                    action.updateAction(actionId, ContextMenuActionItem(id: actionId, text: "Сожжено", textColor: .disabled, icon: icon, action: disabled))
                } else {
                    action.updateAction(actionId, ninegramBurnAction(context: context, message: message, onBurn: onBurn))
                }
            })
        }
    }
    return ContextMenuActionItem(id: actionId, text: message.ninegramMediaBurned ? "Сожжено" : "Сжечь", textColor: message.ninegramMediaBurned ? .disabled : .primary, icon: icon, action: handler)
}
