#import "VoiceMorpherProcessor.h"
#import "OggOpusReader.h"
#import "TGDataItem.h"
#import "TGOggOpusWriter.h"

@implementation VoiceMorpherProcessor

+ (float)pitchShiftForPreset:(VoiceMorpherPreset)preset {
  switch (preset) {
  case VoiceMorpherPresetDisabled:
    return 0;
  case VoiceMorpherPresetAnonymous:
    return -200;
  case VoiceMorpherPresetFemale:
    return 600; // More feminine - higher pitch
  case VoiceMorpherPresetMale:
    return -300;
  case VoiceMorpherPresetChild:
    return 600;
  case VoiceMorpherPresetRobot:
    return 0;
  }
}

+ (float)rateForPreset:(VoiceMorpherPreset)preset {
  switch (preset) {
  case VoiceMorpherPresetDisabled:
    return 1.0;
  case VoiceMorpherPresetAnonymous:
    return 0.95;
  case VoiceMorpherPresetFemale:
    return 1.08; // Slightly faster for feminine effect
  case VoiceMorpherPresetMale:
    return 0.95;
  case VoiceMorpherPresetChild:
    return 1.1;
  case VoiceMorpherPresetRobot:
    return 1.0;
  }
}

+ (void)processOggData:(NSData *)inputData
                preset:(VoiceMorpherPreset)preset
            completion:
                (void (^)(NSData *_Nullable, NSError *_Nullable))completion {

  if (preset == VoiceMorpherPresetDisabled) {
    completion(inputData, nil);
    return;
  }

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                 ^{
                   NSError *error = nil;
                   NSData *result = [self processOggDataSync:inputData
                                                      preset:preset
                                                       error:&error];

                   // Call completion on background thread to avoid deadlock
                   // when caller uses semaphore on main thread
                   completion(result, error);
                 });
}

+ (NSData *_Nullable)processOggDataSync:(NSData *)inputData
                                 preset:(VoiceMorpherPreset)preset
                                  error:(NSError **)error {
  // Save input OGG to temp file for decoding
  NSString *tempInputPath = [NSTemporaryDirectory()
      stringByAppendingPathComponent:
          [NSString
              stringWithFormat:@"vm_in_%lld.ogg", (long long)[[NSDate date]
                                                      timeIntervalSince1970] *
                                                      1000]];

  [inputData writeToFile:tempInputPath atomically:YES];

  // Decode OGG to PCM
  OggOpusReader *reader = [[OggOpusReader alloc] initWithPath:tempInputPath];
  if (!reader) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"VoiceMorpher"
                     code:1
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Failed to open OGG file"
                 }];
    }
    [[NSFileManager defaultManager] removeItemAtPath:tempInputPath error:nil];
    return nil;
  }

  // Opus outputs 16-bit stereo at 48kHz
  NSMutableData *pcmData = [[NSMutableData alloc] init];
  int16_t buffer[5760 * 2]; // Max frame size * channels
  int32_t samplesRead;

  while ((samplesRead = [reader read:buffer
                             bufSize:sizeof(buffer) / sizeof(buffer[0])]) > 0) {
    [pcmData appendBytes:buffer length:samplesRead * sizeof(int16_t)];
  }

  [[NSFileManager defaultManager] removeItemAtPath:tempInputPath error:nil];

  if (pcmData.length == 0) {
    if (error) {
      *error =
          [NSError errorWithDomain:@"VoiceMorpher"
                              code:2
                          userInfo:@{
                            NSLocalizedDescriptionKey : @"No PCM data decoded"
                          }];
    }
    return nil;
  }

  // Apply voice effects using AVAudioEngine
  NSData *processedPcm = [self applyEffectsToPcmData:pcmData
                                              preset:preset
                                               error:error];
  if (!processedPcm) {
    return nil;
  }

  // Encode processed PCM back to OGG
  TGDataItem *dataItem = [[TGDataItem alloc] init];
  TGOggOpusWriter *writer = [[TGOggOpusWriter alloc] init];

  if (![writer beginWithDataItem:dataItem]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"VoiceMorpher"
                     code:4
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Failed to begin OGG encoding"
                 }];
    }
    return nil;
  }

  // Write PCM data in frames (960 samples = 20ms at 48kHz)
  const int frameSize = 960 * sizeof(int16_t);
  const uint8_t *bytes = processedPcm.bytes;
  NSUInteger remaining = processedPcm.length;
  NSUInteger offset = 0;

  while (remaining >= frameSize) {
    [writer writeFrame:(uint8_t *)(bytes + offset) frameByteCount:frameSize];
    offset += frameSize;
    remaining -= frameSize;
  }

  if (remaining > 0) {
    uint8_t lastFrame[frameSize];
    memset(lastFrame, 0, frameSize);
    memcpy(lastFrame, bytes + offset, remaining);
    [writer writeFrame:lastFrame frameByteCount:frameSize];
  }

  return [dataItem data];
}

+ (NSData *_Nullable)applyEffectsToPcmData:(NSData *)pcmData
                                    preset:(VoiceMorpherPreset)preset
                                     error:(NSError **)error {
  NSUInteger sampleCount = pcmData.length / sizeof(int16_t);
  const int16_t *int16Samples = (const int16_t *)pcmData.bytes;

  float *floatSamples = (float *)malloc(sampleCount * sizeof(float));
  if (!floatSamples) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"VoiceMorpher"
                     code:5
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Memory allocation failed"
                 }];
    }
    return nil;
  }

  // Convert int16 to float (-1.0 to 1.0 range)
  for (NSUInteger i = 0; i < sampleCount; i++) {
    floatSamples[i] = (float)int16Samples[i] / 32768.0f;
  }

  // Create audio format (mono, 48kHz, float)
  AVAudioFormat *format =
      [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                       sampleRate:48000
                                         channels:1
                                      interleaved:NO];

  AVAudioFrameCount frameCount = (AVAudioFrameCount)sampleCount;
  AVAudioPCMBuffer *inputBuffer =
      [[AVAudioPCMBuffer alloc] initWithPCMFormat:format
                                    frameCapacity:frameCount];
  inputBuffer.frameLength = frameCount;

  memcpy(inputBuffer.floatChannelData[0], floatSamples,
         sampleCount * sizeof(float));
  free(floatSamples);

  // Create engine and nodes
  AVAudioEngine *engine = [[AVAudioEngine alloc] init];
  AVAudioPlayerNode *playerNode = [[AVAudioPlayerNode alloc] init];
  AVAudioUnitTimePitch *pitchNode = [[AVAudioUnitTimePitch alloc] init];

  pitchNode.pitch = [self pitchShiftForPreset:preset];
  pitchNode.rate = [self rateForPreset:preset];

  [engine attachNode:playerNode];
  [engine attachNode:pitchNode];
  [engine connect:playerNode to:pitchNode format:format];

  AVAudioNode *lastNode = pitchNode;

  if (preset == VoiceMorpherPresetRobot) {
    AVAudioUnitDistortion *distortion = [[AVAudioUnitDistortion alloc] init];
    [distortion loadFactoryPreset:AVAudioUnitDistortionPresetSpeechRadioTower];
    distortion.wetDryMix = 40;
    [engine attachNode:distortion];
    [engine connect:pitchNode to:distortion format:format];
    lastNode = distortion;
  } else if (preset == VoiceMorpherPresetAnonymous) {
    AVAudioUnitDistortion *distortion = [[AVAudioUnitDistortion alloc] init];
    [distortion
        loadFactoryPreset:AVAudioUnitDistortionPresetSpeechCosmicInterference];
    distortion.wetDryMix = 30;
    [engine attachNode:distortion];
    [engine connect:pitchNode to:distortion format:format];
    lastNode = distortion;
  }

  [engine connect:lastNode to:engine.mainMixerNode format:format];

  __block NSMutableData *outputData = [[NSMutableData alloc] init];

  [engine.mainMixerNode
      installTapOnBus:0
           bufferSize:4096
               format:format
                block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
                  float *samples = buffer.floatChannelData[0];
                  AVAudioFrameCount count = buffer.frameLength;

                  int16_t *int16Buffer =
                      (int16_t *)malloc(count * sizeof(int16_t));
                  for (AVAudioFrameCount i = 0; i < count; i++) {
                    float sample = samples[i];
                    if (sample > 1.0f)
                      sample = 1.0f;
                    if (sample < -1.0f)
                      sample = -1.0f;
                    int16Buffer[i] = (int16_t)(sample * 32767.0f);
                  }

                  [outputData appendBytes:int16Buffer
                                   length:count * sizeof(int16_t)];
                  free(int16Buffer);
                }];

  NSError *startError = nil;
  [engine startAndReturnError:&startError];
  if (startError) {
    if (error) {
      *error = startError;
    }
    return nil;
  }

  [playerNode scheduleBuffer:inputBuffer
                      atTime:nil
                     options:0
           completionHandler:nil];
  [playerNode play];

  float rate = [self rateForPreset:preset];
  NSTimeInterval duration = (double)sampleCount / 48000.0 / rate + 0.5;
  [NSThread sleepForTimeInterval:duration];

  [playerNode stop];
  [engine.mainMixerNode removeTapOnBus:0];
  [engine stop];

  return outputData;
}

@end
