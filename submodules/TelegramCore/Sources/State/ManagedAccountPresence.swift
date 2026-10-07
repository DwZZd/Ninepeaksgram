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
    private var requestedOnline: Bool?
    private var requestInProgress = false
    private var requestGeneration = 0
    
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
    ///   2. Ghost Mode / automatic offline → explicitly send offline
    ///   3. Default app behaviour (wasOnline)
    private func refreshPresence() {
        let alwaysOnline = MiscSettingsManager.shared.shouldAlwaysBeOnline
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
        // A timer or settings notification must not cancel an unfinished request
        // for the same state. Slow connections could otherwise never go offline.
        if self.requestInProgress && self.requestedOnline == online {
            return
        }
        self.requestedOnline = online
        self.requestInProgress = true
        self.requestGeneration += 1
        let generation = self.requestGeneration
        self.onlineTimer?.invalidate()
        self.onlineTimer = nil
        let request: Signal<Api.Bool, MTRpcError>
        if online {
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
        } else {
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        }
        
        self.isPerformingUpdate.set(true)
        self.currentRequestDisposable.set((request
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> deliverOn(self.queue)).start(completed: { [weak self] in
            guard let self, self.requestGeneration == generation else { return }
            self.requestInProgress = false
            self.isPerformingUpdate.set(false)
            // Schedule after completion, so retries cannot cancel the RPC. Normal
            // background offline sends once; privacy mode refreshes while active.
            let enforceOffline = self.wasOnline && (GhostModeManager.shared.shouldForceOffline || GhostModeManager.shared.shouldHideOnlineStatus)
            if online || enforceOffline {
                let timer = SignalKitTimer(timeout: online ? 30.0 : 2.0, repeat: false, completion: { [weak self] in
                    self?.refreshPresence()
                }, queue: self.queue)
                self.onlineTimer = timer
                timer.start()
            }
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
