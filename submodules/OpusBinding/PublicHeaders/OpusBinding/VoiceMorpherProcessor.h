#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// VoiceMorpherProcessor - Processes OGG/Opus audio with voice effects
/// Decodes OGG -> applies effects -> re-encodes to OGG
@interface VoiceMorpherProcessor : NSObject

typedef NS_ENUM(NSInteger, VoiceMorpherPreset) {
  VoiceMorpherPresetDisabled = 0,
  VoiceMorpherPresetAnonymous = 1,
  VoiceMorpherPresetFemale = 2,
  VoiceMorpherPresetMale = 3,
  VoiceMorpherPresetChild = 4,
  VoiceMorpherPresetRobot = 5
};

/// Process OGG audio data with voice morphing effect
/// @param inputData Original OGG/Opus audio data
/// @param preset Voice morphing preset to apply
/// @param completion Callback with processed OGG data or error
+ (void)processOggData:(NSData *)inputData
                preset:(VoiceMorpherPreset)preset
            completion:(void (^)(NSData *_Nullable outputData,
                                 NSError *_Nullable error))completion;

/// Get pitch shift value for preset
+ (float)pitchShiftForPreset:(VoiceMorpherPreset)preset;

/// Get rate multiplier for preset
+ (float)rateForPreset:(VoiceMorpherPreset)preset;

@end

NS_ASSUME_NONNULL_END
