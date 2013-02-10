/*
 Copyright (c) Kevin P Murphy June 2012
 
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#import "AudioController.h"
#import <Accelerate/Accelerate.h>

// some MIDI constants:
enum {
	kMIDIMessage_NoteOn    = 0x9,
	kMIDIMessage_NoteOff   = 0x8,
};

#define kOutputBus 0
#define kInputBus 1

@interface AudioController ()
@property (readwrite) Float64   graphSampleRate;
@property (readwrite) AUGraph   processingGraph;
@property (readwrite) AudioUnit samplerUnit;
@property (readwrite) AudioUnit mixerUnit;
@property (readwrite) AudioUnit ioUnit;

- (OSStatus)    loadSynthFromPresetURL:(NSURL *) presetURL;
- (void)        registerForUIApplicationNotifications;
- (BOOL)        createAUGraph;
- (void)        configureAndStartAudioProcessingGraph: (AUGraph) graph;
- (void)        stopAudioProcessingGraph;
- (void)        restartAudioProcessingGraph;
@end


@implementation AudioController
@synthesize rioUnit, mixerUnit, audioFormat, delegate, input, output;
@synthesize graphSampleRate     = _graphSampleRate;
@synthesize samplerUnit         = _samplerUnit;
@synthesize ioUnit              = _ioUnit;
@synthesize processingGraph     = _processingGraph;
Float64 graphSampleRate = 44100.0;


+ (AudioController *) sharedAudioManager
{
    static AudioController *sharedAudioManager;
    
    @synchronized(self)
    {
        if (!sharedAudioManager) {
            sharedAudioManager = [[AudioController alloc] init];
        }
        return sharedAudioManager;
    }
}


void checkStatus(OSStatus status);
void checkStatus(OSStatus status) {
    if(status!=0)
        printf("Error: %ld\n", status);
}


void silenceData(AudioBufferList *inData);
void silenceData(AudioBufferList *inData)
{
	for (UInt32 i=0; i < inData->mNumberBuffers; i++)
		memset(inData->mBuffers[i].mData, 0, inData->mBuffers[i].mDataByteSize);
}



-(void) startAudio
{
    OSStatus status = AudioOutputUnitStart(self.rioUnit);
    checkStatus(status);
    printf("Audio Initialized - sampleRate: %f\n", audioFormat.mSampleRate);
}

- (void) stopAudio {
    
    OSStatus status = AudioOutputUnitStop(self.rioUnit);
    checkStatus(status);
    printf("Audio stopped");
}

#pragma mark init

- (id)init
{
    [self createAUGraph];
    
    
    
    OSStatus status;
    status = AudioSessionInitialize(NULL, NULL, NULL, (__bridge void*) self);
    checkStatus(status);
    
    // Describe audio component
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    // Get component
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
    
    // Get audio units
    status = AudioComponentInstanceNew(inputComponent, &rioUnit);
    checkStatus(status);
    
    
    // Enable IO for recording
    UInt32 flag = 1;
    
    status = AudioUnitSetProperty(rioUnit,                                   
                                  kAudioOutputUnitProperty_EnableIO, 
                                  kAudioUnitScope_Input, 
                                  kInputBus,
                                  &flag,
                                  sizeof(flag));
    checkStatus(status);
    
    
    // Describe format
    audioFormat.mSampleRate= 44100.0;
    audioFormat.mFormatID= kAudioFormatLinearPCM;
    audioFormat.mFormatFlags= kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    audioFormat.mFramesPerPacket= 1;
    audioFormat.mChannelsPerFrame= 1;
    audioFormat.mBitsPerChannel= 16;
    audioFormat.mBytesPerPacket= 2;
    audioFormat.mBytesPerFrame= 2;
    
    self.graphSampleRate = audioFormat.mSampleRate;
    
    // Apply format
    status = AudioUnitSetProperty(rioUnit, 
                                  kAudioUnitProperty_StreamFormat, 
                                  kAudioUnitScope_Output, 
                                  kInputBus, 
                                  &audioFormat, 
                                  sizeof(audioFormat));
    checkStatus(status);
    
    status = AudioUnitSetProperty(rioUnit, 
                                  kAudioUnitProperty_StreamFormat, 
                                  kAudioUnitScope_Input, 
                                  kOutputBus, 
                                  &audioFormat, 
                                  sizeof(audioFormat));
    checkStatus(status);
    
    // Set input callback
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = recordingCallback;
    callbackStruct.inputProcRefCon = (__bridge void*)self;
    
    status = AudioUnitSetProperty(rioUnit, 
                                  kAudioOutputUnitProperty_SetInputCallback, 
                                  kAudioUnitScope_Global, 
                                  kInputBus, 
                                  &callbackStruct, 
                                  sizeof(callbackStruct));
    checkStatus(status);
    
    
    // Disable buffer allocation for the recorder
    flag = 0;
    status = AudioUnitSetProperty(rioUnit, kAudioUnitProperty_ShouldAllocateBuffer, kAudioUnitScope_Global, kInputBus, &flag, sizeof(flag));
    
    
    // Initialise
    UInt32 category = kAudioSessionCategory_PlayAndRecord;
    status = AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(category), &category);
    checkStatus(status);
    
    status = 0;
    UInt32 sampleRatePropertySize = sizeof (self.graphSampleRate);
    status =    AudioUnitSetProperty (
                                      self.samplerUnit,
                                      kAudioUnitProperty_SampleRate,
                                      kAudioUnitScope_Output,
                                      0,
                                      &_graphSampleRate,
                                      sampleRatePropertySize
                                      );
    checkStatus(status);
    
    
    UInt32 framesPerSlice = 0;
    UInt32 framesPerSlicePropertySize = sizeof (framesPerSlice);
    status = 0;
    status =    AudioUnitGetProperty (
                                      self.ioUnit,
                                      kAudioUnitProperty_MaximumFramesPerSlice,
                                      kAudioUnitScope_Global,
                                      0,
                                      &framesPerSlice,
                                      &framesPerSlicePropertySize
                                      );
    checkStatus(status);
    
    status = 0;
    status =    AudioUnitSetProperty (
                                      self.samplerUnit,
                                      kAudioUnitProperty_MaximumFramesPerSlice,
                                      kAudioUnitScope_Global,
                                      0,
                                      &framesPerSlice,
                                      framesPerSlicePropertySize
                                      );
    checkStatus(status);
    
    if (self.processingGraph) {
        status = 0;

        // Initialize the audio processing graph.
        status = AUGraphInitialize (self.processingGraph);
        checkStatus(status);
        status = 0;

        // Start the graph
        status = AUGraphStart (self.processingGraph);
        checkStatus(status);
        
        // Print out the graph to the console
        CAShow (self.processingGraph);
    }
    
    
    status = 0;
    status = AudioSessionSetActive(YES);
    checkStatus(status);
    
    status = AudioUnitInitialize(rioUnit);
    checkStatus(status);
    [self enableMixerInput: 0 isOn: YES];
    [self enableMixerInput: 1 isOn: YES];
    
    [self setMixerOutputGain: 0.5];
    
    [self setMixerInput: 0 gain: 0.5];
    [self setMixerInput: 1 gain: 0.5];
    


    
    return self;
}


- (BOOL) createAUGraph {
    
	OSStatus result = noErr;
	AUNode samplerNode, mixerNode, ioNode;
    
    // Specify the common portion of an audio unit's identify, used for both audio units
    // in the graph.
	AudioComponentDescription cd;
	cd.componentManufacturer     = kAudioUnitManufacturer_Apple;
	cd.componentFlags            = 0;
	cd.componentFlagsMask        = 0;
    
    
    // Multichannel mixer unit
    AudioComponentDescription MixerUnitDescription;
    MixerUnitDescription.componentType          = kAudioUnitType_Mixer;
    MixerUnitDescription.componentSubType       = kAudioUnitSubType_MultiChannelMixer;
    MixerUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
    MixerUnitDescription.componentFlags         = 0;
    MixerUnitDescription.componentFlagsMask     = 0;

    
    // Instantiate an audio processing graph
	result = NewAUGraph (&_processingGraph);
    checkStatus(result);
    
    
	//Specify the Sampler unit, to be used as the first node of the graph
	cd.componentType = kAudioUnitType_MusicDevice;
	cd.componentSubType = kAudioUnitSubType_Sampler;
	
    // Add the Sampler unit node to the graph
	result = AUGraphAddNode (self.processingGraph, &cd, &samplerNode);
    checkStatus(result);
    
    
    result = AUGraphAddNode(self.processingGraph, &MixerUnitDescription, &mixerNode);
    checkStatus(result);
    
	// Specify the Output unit, to be used as the second and final node of the graph
	cd.componentType = kAudioUnitType_Output;
	cd.componentSubType = kAudioUnitSubType_RemoteIO;
    
    // Add the Output unit node to the graph
	result = AUGraphAddNode (self.processingGraph, &cd, &ioNode);
    checkStatus(result);
    
    // Open the graph
	result = AUGraphOpen (self.processingGraph);
    checkStatus(result);
    
    // Connect the Sampler unit to the output unit
	//result = AUGraphConnectNodeInput (self.processingGraph, samplerNode, 0, ioNode, 0);
    checkStatus(result);
    
    
	// Obtain a reference to the Sampler unit from its node
	result = AUGraphNodeInfo (self.processingGraph, samplerNode, 0, &_samplerUnit);
    checkStatus(result);
    
    
    //reference to Mixer
    result =    AUGraphNodeInfo (
                                 self.processingGraph,
                                 mixerNode,
                                 NULL,
                                 &mixerUnit
                                 );
    checkStatus(result);
    
	// Obtain a reference to the I/O unit from its node
	result = AUGraphNodeInfo (self.processingGraph, ioNode, 0, &_ioUnit);
    checkStatus(result);
    
    
    
    UInt32 busCount   = 2;    // bus count for mixer unit input
    UInt32 customBus   = 1;    // mixer unit bus 1 will be mono and will take the beats sound
    
    result = AudioUnitSetProperty (
                                   mixerUnit,
                                   kAudioUnitProperty_ElementCount,
                                   kAudioUnitScope_Input,
                                   0,
                                   &busCount,
                                   sizeof (busCount)
                                   );
    
    
    // Attach the input render callback and context to each input bus
        
        // Setup the struture that contains the input render callback
    AURenderCallbackStruct inputCallbackStruct;
    inputCallbackStruct.inputProc        = &inputRenderCallback;
    inputCallbackStruct.inputProcRefCon  = (__bridge void*) self;
    
        // Set a callback for the specified node's specified input
        result = AUGraphSetNodeInputCallback (
                                              self.processingGraph,
                                              mixerNode,
                                              customBus,
                                              &inputCallbackStruct
                                              );
    
        checkStatus(result);
        
        if (noErr != result) {
            NSLog(@"AUGraphSetNodeInputCallback  %lu", result);
        }
        
    
    AudioStreamBasicDescription stereoStreamFormat;
    stereoStreamFormat.mFormatID          = kAudioFormatLinearPCM;
    stereoStreamFormat.mFormatFlags       = kAudioFormatFlagsAudioUnitCanonical;
    stereoStreamFormat.mBytesPerPacket    = 2;
    stereoStreamFormat.mFramesPerPacket   = 1;
    stereoStreamFormat.mBytesPerFrame     = 2;
    stereoStreamFormat.mChannelsPerFrame  = 2;                    // 2 indicates stereo
    stereoStreamFormat.mBitsPerChannel    = 8 * 2;
    stereoStreamFormat.mSampleRate        = 44100;
    
    AudioStreamBasicDescription monoStreamFormat;
    monoStreamFormat.mSampleRate= 44100;
    monoStreamFormat.mFormatID= kAudioFormatLinearPCM;
    monoStreamFormat.mFormatFlags= kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    monoStreamFormat.mFramesPerPacket= 1;
    monoStreamFormat.mChannelsPerFrame= 1;
    monoStreamFormat.mBitsPerChannel= 16;
    monoStreamFormat.mBytesPerPacket= 2;
    monoStreamFormat.mBytesPerFrame= 2;
    
    
    NSLog (@"Setting stereo stream format for mixer unit \"guitar\" input bus");
    result = AudioUnitSetProperty (
                                   mixerUnit,
                                   kAudioUnitProperty_StreamFormat,
                                   kAudioUnitScope_Input,
                                   0,
                                   &stereoStreamFormat,
                                   sizeof (stereoStreamFormat)
                                   );
    checkStatus(result);
    
    stereoStreamFormat.mChannelsPerFrame = 1;
    NSLog (@"Setting mono stream format for mixer unit \"beats\" input bus");
    result = AudioUnitSetProperty (
                                   mixerUnit,
                                   kAudioUnitProperty_StreamFormat,
                                   kAudioUnitScope_Input,
                                   1,
                                   &monoStreamFormat,
                                   sizeof (monoStreamFormat)
                                   );
    checkStatus(result);
    
    result = AUGraphConnectNodeInput(self.processingGraph, samplerNode, 0, mixerNode, 0);
    checkStatus(result);
    
    if (noErr != result) {
        NSLog(@"AUGraphSetNodeInputCallback  %lu", result);
    }
    
    
    
	result = AUGraphConnectNodeInput (self.processingGraph, mixerNode, 0, ioNode, 0);

    CAShow(self.processingGraph);
    

    
    return YES;
}


-(OSStatus) loadFromDLSOrSoundFontName: (NSString *)name withPatch: (int)presetNumber {
    NSURL *bankURL;
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"sf2"];
    if([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        bankURL = [[NSURL alloc] initFileURLWithPath:path];
    } else {
		NSLog(@"ERROR: Could not get PRESET URL");
    }
    
    OSStatus result = noErr;
    
    
    // fill out a bank preset data structure
    AUSamplerBankPresetData bpdata;
    bpdata.bankURL  = (__bridge CFURLRef) bankURL;
    bpdata.bankMSB  = kAUSampler_DefaultMelodicBankMSB;
    bpdata.bankLSB  = kAUSampler_DefaultBankLSB;
    bpdata.presetID = (UInt8) presetNumber;
    
    // set the kAUSamplerProperty_LoadPresetFromBank property
    result = AudioUnitSetProperty(self.samplerUnit,
                                  kAUSamplerProperty_LoadPresetFromBank,
                                  kAudioUnitScope_Global,
                                  0,
                                  &bpdata,
                                  sizeof(bpdata));
    
    NSCAssert2(result==noErr, @"Unable to set SF2 on Sampler...  Error code:%d '%.4s", (int) result,  (const char*) &result);
    
    return result;
}


- (OSStatus) loadSynthFromPresetURL: (NSURL *) presetURL {
    
    NSURL *ppresetURL = [[NSURL alloc] initFileURLWithPath:[[NSBundle mainBundle] pathForResource:@"Vibraphone" ofType:@"aupreset"]];
	if (ppresetURL) {
		//NSLog(@"LoadingPreset '%@'\n", [presetURL description]);
        presetURL = ppresetURL;
    } else {
		NSLog(@"ERROR: Could not get PRESET URL");
	}
    
    
	CFDataRef propertyResourceData = 0;
	Boolean status;
	SInt32 errorCode = 0;
	OSStatus result = noErr;
	
	// Read from the URL and convert into a CFData chunk
	status = CFURLCreateDataAndPropertiesFromResource (
                                                       kCFAllocatorDefault,
                                                       (__bridge CFURLRef) presetURL,
                                                       &propertyResourceData,
                                                       NULL,
                                                       NULL,
                                                       &errorCode
                                                       );
    
    checkStatus(status);
   	
	// Convert the data object into a property list
	CFPropertyListRef presetPropertyList = 0;
	CFPropertyListFormat dataFormat = (CFPropertyListFormat) 0;
	CFErrorRef errorRef = 0;
	presetPropertyList = CFPropertyListCreateWithData (
                                                       kCFAllocatorDefault,
                                                       propertyResourceData,
                                                       kCFPropertyListImmutable,
                                                       &dataFormat,
                                                       &errorRef
                                                       );
    
    // Set the class info property for the Sampler unit using the property list as the value.
	if (presetPropertyList != 0) {
		
		result = AudioUnitSetProperty(
                                      self.samplerUnit,
                                      kAudioUnitProperty_ClassInfo,
                                      kAudioUnitScope_Global,
                                      0,
                                      &presetPropertyList,
                                      sizeof(CFPropertyListRef)
                                      );
        
		CFRelease(presetPropertyList);
	}
    
    if (errorRef) CFRelease(errorRef);
	CFRelease (propertyResourceData);
    
    
	return result;
}


double theta = 0;
void generateSine(SInt16 *sampleBuffer, int numFrames, float sampleRate, float freq) {
    float deltaTheta = 2*M_PI*(freq/sampleRate);
    for(int i = 0; i<numFrames; i++) {
        sampleBuffer[i] = (SInt16) (0.8 * SHRT_MAX * sin(theta));
        theta += deltaTheta;
        if(theta>2*M_PI) theta = theta - 2*M_PI;
        
    }
}

int squareIndex = 0;
int amp = SHRT_MAX * 0.8;
void generateSquare(SInt16 *sampleBuffer, int numFrames, float sampleRate, float frequency) {
    float samplesPerCycle = sampleRate/frequency;
    for(int i = 0; i < numFrames; i++) {
        
        if(fmodf(squareIndex, samplesPerCycle)/samplesPerCycle > 0.5) {
            sampleBuffer[i] = amp;
        } else {
            sampleBuffer[i] = -1*amp;
        }
        
        squareIndex = squareIndex+1;
        
        if(squareIndex >= samplesPerCycle) squareIndex-=samplesPerCycle;
    }
}


BOOL shouldPlay = NO;
int number = 0;
static OSStatus inputRenderCallback (
                                     
                                     void                        *inRefCon,      // A pointer to a struct containing the complete audio data
                                     //    to play, as well as state information such as the
                                     //    first sample to play on this invocation of the callback.
                                     AudioUnitRenderActionFlags  *ioActionFlags, // Unused here. When generating audio, use ioActionFlags to indicate silence
                                     //    between sounds; for silence, also memset the ioData buffers to 0.
                                     const AudioTimeStamp        *inTimeStamp,   // Unused here.
                                     UInt32                      inBusNumber,    // The mixer unit input bus that is requesting some new
                                     //        frames of audio data to play.
                                     UInt32                      inNumberFrames, // The number of frames of audio to provide to the buffer(s)
                                     //        pointed to by the ioData parameter.
                                     AudioBufferList             *ioData         // On output, the audio data to play. The callback's primary
                                     //        responsibility is to fill the buffer(s) in the
                                     //        AudioBufferList.
                                     ) {
    AudioController *THIS = (__bridge AudioController*) inRefCon;
    SInt16 *temp = (SInt16 *) ioData->mBuffers[0].mData;
    
    generateSquare(temp, inNumberFrames, 44100, 440);
    
    return  noErr;
    
    if(!THIS.output) {
        memset(temp, 0, inNumberFrames*sizeof(SInt16));
        return noErr;
    }
    
    return noErr;
}


#pragma mark Recording Callback
static OSStatus recordingCallback(void *inRefCon,
                                  AudioUnitRenderActionFlags *ioActionFlags,
                                  const AudioTimeStamp *inTimeStamp,
                                  UInt32 inBusNumber,
                                  UInt32 inNumberFrames,
                                  AudioBufferList *ioData) {
    
    AudioController *THIS = (__bridge AudioController*) inRefCon;
    
    if(!THIS.input) return noErr;
    
    THIS->bufferList.mNumberBuffers = 1;
    THIS->bufferList.mBuffers[0].mDataByteSize = sizeof(SInt16)*inNumberFrames;
    THIS->bufferList.mBuffers[0].mNumberChannels = 1;
    THIS->bufferList.mBuffers[0].mData = (SInt16*) malloc(sizeof(SInt16)*inNumberFrames);
    
    OSStatus status;
    
    status = AudioUnitRender(THIS->rioUnit,
                             ioActionFlags,
                             inTimeStamp,
                             inBusNumber,
                             inNumberFrames,
                             &(THIS->bufferList));
    checkStatus(status);
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [THIS.delegate receivedAudioSamples:(SInt16*)THIS->bufferList.mBuffers[0].mData length:inNumberFrames];
    });
    
    return noErr;
}


- (void) playNote:(int) notenumm {
    UInt32 noteNum = notenumm;
	UInt32 onVelocity = 100;
	UInt32 noteCommand = 	kMIDIMessage_NoteOn << 4 | 0;
	
    OSStatus result = noErr;
    result = MusicDeviceMIDIEvent(self.samplerUnit, noteCommand, noteNum, onVelocity, 0);
    checkStatus(result);
}

- (void) stopNote:(int) notenumm {
    UInt32 noteNum = notenumm;
	UInt32 onVelocity = 100;
	UInt32 noteCommand = 	kMIDIMessage_NoteOff << 4 | 0;
	
    OSStatus result = noErr;
    result = MusicDeviceMIDIEvent(self.samplerUnit, noteCommand, noteNum, onVelocity, 0);
    checkStatus(result);
}


#pragma mark -
#pragma mark Mixer unit control
// Enable or disable a specified bus
- (void) enableMixerInput: (UInt32) inputBus isOn: (AudioUnitParameterValue) isOnValue {
    
    NSLog (@"Bus %d now %@", (int) inputBus, isOnValue ? @"on" : @"off");
    
    OSStatus result = AudioUnitSetParameter (
                                             mixerUnit,
                                             kMultiChannelMixerParam_Enable,
                                             kAudioUnitScope_Input,
                                             inputBus,
                                             isOnValue,
                                             0
                                             );
    
    checkStatus(result);
}


// Set the mixer unit input volume for a specified bus
- (void) setMixerInput: (UInt32) inputBus gain: (AudioUnitParameterValue) newGain {
    
    OSStatus result = AudioUnitSetParameter (
                                             mixerUnit,
                                             kMultiChannelMixerParam_Volume,
                                             kAudioUnitScope_Input,
                                             inputBus,
                                             newGain,
                                             0
                                             );
    checkStatus(result);
}


// Set the mxer unit output volume
- (void) setMixerOutputGain: (AudioUnitParameterValue) newGain {
    OSStatus result = AudioUnitSetParameter (
                                             mixerUnit,
                                             kMultiChannelMixerParam_Volume,
                                             kAudioUnitScope_Output,
                                             0,
                                             newGain,
                                             0
                                             );
    checkStatus(result);

}



@end
