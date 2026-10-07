import Foundation
import AVFoundation

/// VoiceMorpherManager - Manages voice morphing presets and settings
public final class VoiceMorpherManager {
    public static let shared = VoiceMorpherManager()
    
    // MARK: - Voice Preset
    
    public enum VoicePreset: Int, CaseIterable {
        case disabled = 0
        case anonymous = 1
        case female = 2
        case male = 3
        case child = 4
        case robot = 5
        
        public var name: String {
            switch self {
            case .disabled: return "Выключено"
            case .anonymous: return "Аноним"
            case .female: return "Женский"
            case .male: return "Мужской"
            case .child: return "Ребёнок"
            case .robot: return "Робот"
            }
        }
        
        public var description: String {
            switch self {
            case .disabled: return "Голос без изменений"
            case .anonymous: return "Искаженный голос (как в новостях)"
            case .female: return "Повышенный питч + форманты"
            case .male: return "Пониженный питч + форманты"
            case .child: return "Высокий детский голос"
            case .robot: return "Металлический эффект"
            }
        }
        
        /// Pitch multiplier (1.0 = normal, >1 = higher, <1 = lower)
        public var pitchShift: Float {
            switch self {
            case .disabled: return 0
            case .anonymous: return -200 // semitones down slightly
            case .female: return 600 // More feminine - higher pitch
            case .male: return -300 // semitones down
            case .child: return 600 // high pitch
            case .robot: return 0 // no pitch change for robot
            }
        }
        
        /// Rate adjustment
        public var rate: Float {
            switch self {
            case .disabled: return 1.0
            case .anonymous: return 0.95
            case .female: return 1.08 // Slightly faster for feminine effect
            case .male: return 0.95
            case .child: return 1.1
            case .robot: return 1.0
            }
        }
        
        /// Distortion preset for robot effect
        public var useDistortion: Bool {
            return self == .robot || self == .anonymous
        }
        
        /// Reverb amount (0-100)
        public var reverbAmount: Float {
            switch self {
            case .anonymous: return 20
            case .robot: return 30
            default: return 0
            }
        }
    }
    
    // MARK: - Keys
    
    private enum Keys {
        static let isEnabled = "VoiceMorpher.isEnabled"
        static let selectedPreset = "VoiceMorpher.selectedPreset"
    }
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Properties
    
    /// Whether voice morphing is enabled
    public var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.isEnabled) }
        set {
            defaults.set(newValue, forKey: Keys.isEnabled)
            notifyChanged()
        }
    }
    
    /// Selected preset ID
    public var selectedPresetId: Int {
        get { defaults.integer(forKey: Keys.selectedPreset) }
        set {
            defaults.set(newValue, forKey: Keys.selectedPreset)
            notifyChanged()
        }
    }
    
    /// Get selected preset
    public var selectedPreset: VoicePreset {
        return VoicePreset(rawValue: selectedPresetId) ?? .disabled
    }
    
    /// Get effective preset (returns disabled if not enabled)
    public var effectivePreset: VoicePreset {
        guard isEnabled else { return .disabled }
        return selectedPreset
    }
    
    // MARK: - Notification
    
    public static let settingsChangedNotification = Notification.Name("VoiceMorpherSettingsChanged")
    
    private func notifyChanged() {
        NotificationCenter.default.post(name: Self.settingsChangedNotification, object: nil)
    }
    
    // MARK: - Init
    
    private init() {}
}
