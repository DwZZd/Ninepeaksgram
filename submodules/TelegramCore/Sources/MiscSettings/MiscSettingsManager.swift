import Foundation

/// MiscSettingsManager - Central manager for Misc privacy settings
/// Handles: Forward bypass, View-Once persistence, Screenshot bypass, Block Ads, Always Online
public final class MiscSettingsManager {
    public static let shared = MiscSettingsManager()
    
    private enum Keys {
        static let isEnabled                  = "MiscSettings.isEnabled"
        static let bypassCopyProtection       = "MiscSettings.bypassCopyProtection"
        static let disableViewOnceAutoDelete  = "MiscSettings.disableViewOnceAutoDelete"
        static let bypassScreenshotProtection = "MiscSettings.bypassScreenshotProtection"
        static let blockAds                   = "MiscSettings.blockAds"
        static let alwaysOnline               = "MiscSettings.alwaysOnline"
    }
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Main Toggle
    
    public var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.isEnabled) }
        set {
            defaults.set(newValue, forKey: Keys.isEnabled)
            notifySettingsChanged()
        }
    }
    
    // MARK: - Individual Features
    
    /// Allow forwarding/copying from protected channels and chats
    public var bypassCopyProtection: Bool {
        get { defaults.bool(forKey: Keys.bypassCopyProtection) }
        set {
            defaults.set(newValue, forKey: Keys.bypassCopyProtection)
            notifySettingsChanged()
        }
    }
    
    /// Keep View-Once media visible (don't auto-delete after viewing)
    public var disableViewOnceAutoDelete: Bool {
        get { defaults.bool(forKey: Keys.disableViewOnceAutoDelete) }
        set {
            defaults.set(newValue, forKey: Keys.disableViewOnceAutoDelete)
            notifySettingsChanged()
        }
    }
    
    /// Allow screenshots in secret chats and protected content
    public var bypassScreenshotProtection: Bool {
        get { defaults.bool(forKey: Keys.bypassScreenshotProtection) }
        set {
            defaults.set(newValue, forKey: Keys.bypassScreenshotProtection)
            notifySettingsChanged()
        }
    }
    
    /// Block all sponsored messages (ads) in channels
    public var blockAds: Bool {
        get { defaults.bool(forKey: Keys.blockAds) }
        set {
            defaults.set(newValue, forKey: Keys.blockAds)
            notifySettingsChanged()
        }
    }
    
    /// Always appear as online.
    /// NOTE: Ghost Mode features dynamically yield to Always Online via their
    /// `shouldAlwaysBeOnline` check, so no permanent disabling is needed here.
    public var alwaysOnline: Bool {
        get { defaults.bool(forKey: Keys.alwaysOnline) }
        set {
            defaults.set(newValue, forKey: Keys.alwaysOnline)
            notifySettingsChanged()
        }
    }
    
    // MARK: - Computed Properties (considers master toggle)
    
    public var shouldBypassCopyProtection: Bool {
        return isEnabled && bypassCopyProtection
    }
    
    public var shouldDisableViewOnceAutoDelete: Bool {
        return disableViewOnceAutoDelete
    }
    
    public var shouldBypassScreenshotProtection: Bool {
        return isEnabled && bypassScreenshotProtection
    }
    
    public var shouldBlockAds: Bool {
        return isEnabled && blockAds
    }
    
    public var shouldAlwaysBeOnline: Bool {
        return isEnabled && alwaysOnline
    }
    
    // MARK: - Utility
    
    public var activeFeatureCount: Int {
        var count = 0
        if bypassCopyProtection      { count += 1 }
        if disableViewOnceAutoDelete { count += 1 }
        if bypassScreenshotProtection { count += 1 }
        if blockAds                  { count += 1 }
        if alwaysOnline              { count += 1 }
        return count
    }
    
    public func enableAll() {
        bypassCopyProtection       = true
        disableViewOnceAutoDelete  = true
        bypassScreenshotProtection = true
        blockAds                   = true
        alwaysOnline               = true
    }
    
    public func disableAll() {
        bypassCopyProtection       = false
        disableViewOnceAutoDelete  = false
        bypassScreenshotProtection = false
        blockAds                   = false
        alwaysOnline               = false
    }
    
    // MARK: - Internal mutual exclusion (called by GhostModeManager)
    
    /// Called by GhostModeManager when Ghost Mode is turned on.
    /// Disables Always Online so the two modes don't coexist in the UI.
    public func disableAlwaysOnlineForMutualExclusion() {
        defaults.set(false, forKey: Keys.alwaysOnline)
        notifySettingsChanged()
    }
    
    // MARK: - Notification
    
    public static let settingsChangedNotification = Notification.Name("MiscSettingsChanged")
    
    private func notifySettingsChanged() {
        NotificationCenter.default.post(name: MiscSettingsManager.settingsChangedNotification, object: nil)
    }
    
    // MARK: - Init
    
    private init() {
        if !defaults.bool(forKey: "MiscSettings.initialized") {
            defaults.set(true, forKey: "MiscSettings.initialized")
            defaults.set(true, forKey: Keys.isEnabled)
            defaults.set(true, forKey: Keys.bypassCopyProtection)
            defaults.set(true, forKey: Keys.disableViewOnceAutoDelete)
            defaults.set(true, forKey: Keys.bypassScreenshotProtection)
            defaults.set(true, forKey: Keys.blockAds)
            defaults.set(false, forKey: Keys.alwaysOnline)
        }
    }
}
