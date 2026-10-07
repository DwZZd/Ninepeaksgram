import Foundation
import AVFoundation
import OpusBinding
import TelegramCore

/// VoiceMorpherEngine - Swift wrapper for OGG voice morphing
/// Uses VoiceMorpherProcessor (Obj-C) for OGG decode → effects → encode
public final class VoiceMorpherEngine {
    
    public static let shared = VoiceMorpherEngine()
    
    private init() {}
    
    // MARK: - Process OGG Data
    
    /// Process OGG/Opus audio data with current voice morpher preset
    /// - Parameters:
    ///   - inputData: Original OGG/Opus audio data
    ///   - completion: Callback with processed OGG data or error
    public func processOggData(
        _ inputData: Data,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let preset = VoiceMorpherManager.shared.effectivePreset
        
        // If disabled, return original data
        guard preset != .disabled else {
            completion(.success(inputData))
            return
        }
        
        // Convert Swift preset to ObjC preset
        let objcPreset: VoiceMorpherPreset
        switch preset {
        case .disabled:
            objcPreset = .disabled
        case .anonymous:
            objcPreset = .anonymous
        case .female:
            objcPreset = .female
        case .male:
            objcPreset = .male
        case .child:
            objcPreset = .child
        case .robot:
            objcPreset = .robot
        }
        
        VoiceMorpherProcessor.processOggData(inputData, preset: objcPreset) { outputData, error in
            if let error = error {
                completion(.failure(error))
            } else if let outputData = outputData {
                completion(.success(outputData))
            } else {
                completion(.failure(VoiceMorpherError.processingFailed))
            }
        }
    }
    
    /// Synchronous version for use in existing pipelines
    public func processOggDataSync(_ inputData: Data) -> Data {
        let preset = VoiceMorpherManager.shared.effectivePreset
        
        guard preset != .disabled else {
            return inputData
        }
        
        // Use semaphore for sync call
        let semaphore = DispatchSemaphore(value: 0)
        var result = inputData
        
        processOggData(inputData) { processingResult in
            switch processingResult {
            case .success(let data):
                result = data
            case .failure:
                // On error, return original
                result = inputData
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 30)
        return result
    }
    
    // MARK: - Errors
    
    public enum VoiceMorpherError: Error, LocalizedError {
        case processingFailed
        
        public var errorDescription: String? {
            switch self {
            case .processingFailed:
                return "Voice morphing processing failed"
            }
        }
    }
}
