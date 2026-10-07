import Foundation

/// GhostModeManager - Central manager for Ghost Mode privacy settings
/// Controls all privacy features: hide read receipts, typing indicator, online status, story views
public final class GhostModeManager {
    
    // MARK: - Singleton
    
    public static let shared = GhostModeManager()
    
    // MARK: - UserDefaults Keys
    
    private enum Keys {
        static let isEnabled           = "GhostMode.isEnabled"
        static let hideReadReceipts    = "GhostMode.hideReadReceipts"
        static let hideStoryViews      = "GhostMode.hideStoryViews"
        static let hideOnlineStatus    = "GhostMode.hideOnlineStatus"
        static let hideTypingIndicator = "GhostMode.hideTypingIndicator"
        static let forceOffline        = "GhostMode.forceOffline"
    }
    
    // MARK: - Settings Storage
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Properties
    
    /// Master toggle for Ghost Mode.
    /// Enabling Ghost Mode automatically disables Always Online in MiscSettingsManager.
    public var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.isEnabled) }
        set {
            defaults.set(newValue, forKey: Keys.isEnabled)
            if newValue {
                // Ghost Mode ON → disable Always Online so they don't coexist in UI
                MiscSettingsManager.shared.disableAlwaysOnlineForMutualExclusion()
            }
            notifySettingsChanged()
        }
    }
    
    /// Don't send read receipts (blue checkmarks)
    public var hideReadReceipts: Bool {
        get { defaults.bool(forKey: Keys.hideReadReceipts) }
        set {
            defaults.set(newValue, forKey: Keys.hideReadReceipts)
            notifySettingsChanged()
        }
    }
    
    /// Don't send story view notifications
    public var hideStoryViews: Bool {
        get { defaults.bool(forKey: Keys.hideStoryViews) }
        set {
            defaults.set(newValue, forKey: Keys.hideStoryViews)
            notifySettingsChanged()
        }
    }
    
    /// Don't send online status
    public var hideOnlineStatus: Bool {
        get { defaults.bool(forKey: Keys.hideOnlineStatus) }
        set {
            defaults.set(newValue, forKey: Keys.hideOnlineStatus)
            notifySettingsChanged()
        }
    }
    
    /// Don't send typing indicator
    public var hideTypingIndicator: Bool {
        get { defaults.bool(forKey: Keys.hideTypingIndicator) }
        set {
            defaults.set(newValue, forKey: Keys.hideTypingIndicator)
            notifySettingsChanged()
        }
    }
    
    /// Always appear as offline
    public var forceOffline: Bool {
        get { defaults.bool(forKey: Keys.forceOffline) }
        set {
            defaults.set(newValue, forKey: Keys.forceOffline)
            if newValue {
                MiscSettingsManager.shared.disableAlwaysOnlineForMutualExclusion()
            }
            notifySettingsChanged()
        }
    }
    
    // MARK: - Computed Properties
    
    /// Returns true only when Ghost Mode is enabled AND the individual toggle is on.
    /// NOTE: Always Online takes precedence — if Always Online is active, online status is never hidden.
    public var shouldHideReadReceipts: Bool {
        return isEnabled && hideReadReceipts
    }
    
    public var shouldHideStoryViews: Bool {
        return isEnabled && hideStoryViews
    }
    
    /// Only an enabled Always Online setting can override hidden presence.
    /// A stored toggle in the disabled Misc section must not force us online.
    public var shouldHideOnlineStatus: Bool {
        guard isEnabled && hideOnlineStatus else { return false }
        return !MiscSettingsManager.shared.shouldAlwaysBeOnline
    }
    
    public var shouldHideTypingIndicator: Bool {
        return isEnabled && hideTypingIndicator
    }
    
    /// Automatic offline works independently of the Ghost Mode master toggle.
    public var shouldForceOffline: Bool {
        guard forceOffline else { return false }
        return !MiscSettingsManager.shared.shouldAlwaysBeOnline
    }
    
    /// Count of active features (e.g., "5/5")
    public var activeFeatureCount: Int {
        var count = 0
        if hideReadReceipts    { count += 1 }
        if hideStoryViews      { count += 1 }
        if hideOnlineStatus    { count += 1 }
        if hideTypingIndicator { count += 1 }
        if forceOffline        { count += 1 }
        return count
    }
    
    /// Total number of features
    public static let totalFeatureCount = 5
    
    // MARK: - Initialization
    
    private init() {
        if !defaults.bool(forKey: "GhostMode.initialized") {
            defaults.set(true, forKey: "GhostMode.initialized")
            defaults.set(true, forKey: Keys.hideReadReceipts)
            defaults.set(true, forKey: Keys.hideStoryViews)
            defaults.set(true, forKey: Keys.hideOnlineStatus)
            defaults.set(true, forKey: Keys.hideTypingIndicator)
            defaults.set(true, forKey: Keys.forceOffline)
            defaults.set(false, forKey: Keys.isEnabled)
        }
    }
    
    // MARK: - Enable/Disable All
    
    /// Enable all ghost mode features.
    /// Also disables Always Online (mutual exclusion).
    public func enableAll() {
        hideReadReceipts    = true
        hideStoryViews      = true
        hideOnlineStatus    = true
        hideTypingIndicator = true
        forceOffline        = true
        isEnabled           = true  // setter handles mutual exclusion
    }
    
    /// Disable all ghost mode features
    public func disableAll() {
        isEnabled = false
    }
    
    // MARK: - Notifications
    
    public static let settingsChangedNotification = Notification.Name("GhostModeSettingsChanged")
    
    private func notifySettingsChanged() {
        NotificationCenter.default.post(name: GhostModeManager.settingsChangedNotification, object: nil)
    }
}
