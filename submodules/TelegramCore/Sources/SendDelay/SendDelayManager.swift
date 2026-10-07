import Foundation

/// SendDelayManager - delays outgoing messages by ~12 seconds to prevent
/// online status from appearing after sending.
///
/// Delays are applied per-message at the enqueueMessages level.
/// Media messages receive a slightly longer delay (~20 s) because upload
/// time would otherwise reveal the send moment anyway.
public final class SendDelayManager {

    // MARK: - Singleton

    public static let shared = SendDelayManager()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let isEnabled = "SendDelay.isEnabled"
    }

    // MARK: - Storage

    private let defaults = UserDefaults.standard

    // MARK: - Properties

    /// When true, all outgoing messages are delayed before being enqueued.
    public var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.isEnabled) }
        set {
            defaults.set(newValue, forKey: Keys.isEnabled)
            notifySettingsChanged()
        }
    }

    // MARK: - Delay constants

    /// Base delay for text-only messages.
    public static let textDelaySeconds: Double = 12.0

    /// Delay for messages that contain media attachments.
    public static let mediaDelaySeconds: Double = 20.0

    // MARK: - Init

    private init() {}

    // MARK: - Notifications

    public static let settingsChangedNotification = Notification.Name("SendDelaySettingsChanged")

    private func notifySettingsChanged() {
        NotificationCenter.default.post(name: SendDelayManager.settingsChangedNotification, object: nil)
    }
}
