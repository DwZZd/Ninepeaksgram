import Foundation
import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit

private typealias SignalKitTimer = SwiftSignalKit.Timer


private final class AccountPresenceManagerImpl {
    private let queue: Queue
    private let network: Network
    let isPerformingUpdate = ValuePromise<Bool>(false, ignoreRepeated: true)
    
    private var shouldKeepOnlinePresenceDisposable: Disposable?
    private let currentRequestDisposable = MetaDisposable()
    private var onlineTimer: SignalKitTimer?
    
    // Tracks the last app-level online value so we can refresh independently
    private var wasOnline: Bool = false
    
    // Observers for settings change notifications
    private var ghostModeObserver: NSObjectProtocol?
    private var miscSettingsObserver: NSObjectProtocol?
    
    init(queue: Queue, shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network) {
        self.queue = queue
        self.network = network
        
        self.shouldKeepOnlinePresenceDisposable = (shouldKeepOnlinePresence
        |> distinctUntilChanged
        |> deliverOn(self.queue)).start(next: { [weak self] value in
            guard let self = self else { return }
            self.wasOnline = value
            self.refreshPresence()
        })
        
        // React to Ghost Mode or Always Online settings changes without waiting
        // for the next app focus event.
        let notificationQueue = DispatchQueue.main
        self.ghostModeObserver = NotificationCenter.default.addObserver(
            forName: GhostModeManager.settingsChangedNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            notificationQueue.async {
                self?.queue.async {
                    self?.refreshPresence()
                }
            }
        }
        
        self.miscSettingsObserver = NotificationCenter.default.addObserver(
            forName: MiscSettingsManager.settingsChangedNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            notificationQueue.async {
                self?.queue.async {
                    self?.refreshPresence()
                }
            }
        }
    }
    
    deinit {
        assert(self.queue.isCurrent())
        self.shouldKeepOnlinePresenceDisposable?.dispose()
        self.currentRequestDisposable.dispose()
        self.onlineTimer?.invalidate()
        if let observer = self.ghostModeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = self.miscSettingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /// Compute the effective online state and push it to Telegram.
    /// Priority chain (highest → lowest):
    ///   1. Always Online enabled → force online = true
    ///   2. Ghost Mode hide online status → skip update entirely (freeze last-seen)
    ///   3. Default app behaviour (wasOnline)
    private func refreshPresence() {
        // Use raw alwaysOnline flag (not shouldAlwaysBeOnline) so it works independently
        // of the Misc master toggle. Ghost Mode's shouldHideOnlineStatus already checks
        // !MiscSettingsManager.shared.alwaysOnline internally.
        let alwaysOnline = MiscSettingsManager.shared.alwaysOnline
        let ghostHideOnline = GhostModeManager.shared.shouldHideOnlineStatus
        
        if alwaysOnline {
            // Always Online wins — push online regardless of Ghost Mode
            sendPresenceUpdate(online: true)
        } else if ghostHideOnline || GhostModeManager.shared.shouldForceOffline {
            sendPresenceUpdate(online: false)
        } else {
            // Normal mode — follow the app-level state
            sendPresenceUpdate(online: wasOnline)
        }
    }
    
    private func sendPresenceUpdate(online: Bool) {
        self.onlineTimer?.invalidate()
        self.onlineTimer = nil
        let request: Signal<Api.Bool, MTRpcError>
        if online {
            // Keep pinging every 30 s so the server keeps us online
            let timer = SignalKitTimer(timeout: 30.0, repeat: false, completion: { [weak self] in
                guard let self = self else { return }
                self.refreshPresence()
            }, queue: self.queue)
            self.onlineTimer = timer
            timer.start()
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
        } else {
            let timer = SignalKitTimer(timeout: 2.0, repeat: false, completion: { [weak self] in
                self?.refreshPresence()
            }, queue: self.queue)
            self.onlineTimer = timer
            timer.start()
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        }
        
        self.isPerformingUpdate.set(true)
        self.currentRequestDisposable.set((request
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> deliverOn(self.queue)).start(completed: { [weak self] in
            self?.isPerformingUpdate.set(false)
        }))
    }
}

final class AccountPresenceManager {
    private let queue = Queue()
    private let impl: QueueLocalObject<AccountPresenceManagerImpl>
    
    init(shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: self.queue, generate: {
            return AccountPresenceManagerImpl(queue: queue, shouldKeepOnlinePresence: shouldKeepOnlinePresence, network: network)
        })
    }
    
    func isPerformingUpdate() -> Signal<Bool, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                disposable.set(impl.isPerformingUpdate.get().start(next: { value in
                    subscriber.putNext(value)
                }))
            }
            return disposable
        }
    }
}
