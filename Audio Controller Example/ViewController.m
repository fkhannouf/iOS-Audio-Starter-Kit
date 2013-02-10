//
//  ViewController.m
//  Audio Controller Example
//
//  Created by Kevin Murphy on 2/9/13.
//  Copyright (c) 2013 Kevin Murphy. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
        
    
    UISlider *freqSlider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width*0.8, 80)];
    freqSlider.center = CGPointMake(self.view.bounds.size.width/2, 180);
    freqSlider.minimumValue = log10(300); //LOGSCALE
    freqSlider.maximumValue = log10(8000); //LOGSCALE
    freqSlider.value = log10(440);
    outputFrequency = 440;
    [freqSlider addTarget:self action:@selector(frequencySliderChanged:) forControlEvents:UIControlEventValueChanged];
    
    [self.view addSubview:freqSlider];
    
    UILabel *frequencyLabel = [[UILabel alloc] initWithFrame:CGRectMake(freqSlider.frame.origin.x, freqSlider.frame.origin.y-15, 150, 40)];
    frequencyLabel.backgroundColor = [UIColor clearColor];
    frequencyLabel.text = @"Frequency Slider:";
    frequencyLabel.textColor = [UIColor whiteColor];
    [self.view addSubview:frequencyLabel];
    
    //Amplitude slider and label - on a log scale
    UISlider *ampSlider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width*0.8, 80)];
    ampSlider.center = CGPointMake(self.view.bounds.size.width/2, 100);
    ampSlider.minimumValue = 1; //LOGSCALE
    ampSlider.maximumValue = 2; //LOGSCALE
    ampSlider.value = 2;
    [ampSlider addTarget:self action:@selector(amplitudeSliderChanged:) forControlEvents:UIControlEventValueChanged];
    outputAmplitude = 1;
    [self.view addSubview:ampSlider];
    
    UILabel *ampLabel = [[UILabel alloc] initWithFrame:CGRectMake(ampSlider.frame.origin.x, ampSlider.frame.origin.y-15, 150, 40)];
    ampLabel.backgroundColor = [UIColor clearColor];
    ampLabel.text = @"Amplitude Slider:";
    ampLabel.textColor = [UIColor whiteColor];
    [self.view addSubview:ampLabel];
    
    //Set up segment controller that will select the sine shape
    waveControl = [[UISegmentedControl alloc] initWithItems:[NSArray arrayWithObjects:@"Sine", @"Square", @"Tri", @"Saw", nil]];
    waveControl.selectedSegmentIndex = 0;    
    waveControl.center = CGPointMake(freqSlider.center.x, freqSlider.center.y+90);
    [self.view addSubview:waveControl];
    
    //MIDI Button
    UIButton *midiButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [midiButton setTitle:@"Play Note" forState:UIControlStateNormal];
    [midiButton addTarget:self action:@selector(playNote) forControlEvents:UIControlEventTouchUpInside];
    [midiButton setFrame:CGRectMake(0, 0, 200, 50)];
    [midiButton setCenter:CGPointMake(self.view.frame.size.width/2, self.view.bounds.size.height-50)];
    [self.view addSubview:midiButton];
    
    //Meter view
    audioMeter = [[MeterView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 20)];
    audioMeter.center = CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height-10);
    [self.view addSubview:audioMeter];
}

- (void) viewDidAppear:(BOOL)animated {
    //Start Audio, set this view controller as a delegate, and then turn on input and output.
    
    [AudioController sharedAudioManager];
    [AudioController sharedAudioManager].delegate = self;
    [AudioController sharedAudioManager].input = true;
    [AudioController sharedAudioManager].output = true;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Frequency and Amplitude control -

- (void) frequencySliderChanged:(id) sender {
    float thisValue = pow(10,[(UISlider*)sender value]);
    outputFrequency = thisValue;
}

- (void) amplitudeSliderChanged:(id) sender {
    float thisValue = (pow(10,[(UISlider*)sender value])-10)/90; // the "-10)/90" is so I can scale the logarithmic amplitude from 0-1.0
    outputAmplitude = thisValue;
}

#pragma mark - Basic Waveform Factory Methods -
//For more info on the concept behind these factory methods, go back to my blog http://kevmdev.com/blog to learn more
double theta = 0;
void generateSine(SInt16 *sampleBuffer, int numFrames, float sampleRate, float freq, float amp) {
    if(amp>1) amp=1;
    if(amp<0) amp=0;
    amp = amp * SHRT_MAX;
    float deltaTheta = 2*M_PI*(freq/sampleRate);
    for(int i = 0; i<numFrames; i++) {
        sampleBuffer[i] = (SInt16) (amp * sin(theta));
        theta += deltaTheta;
        if(theta>2*M_PI) theta = theta - 2*M_PI;
        
    }
}

int squareIndex = 0;
void generateSquare(SInt16 *sampleBuffer, int numFrames, float sampleRate, float frequency, float amp) {
    if(amp>1) amp=1;
    if(amp<0) amp=0;
    amp = amp*SHRT_MAX;
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

int sawIndex = 0;
void generateSawtooth(SInt16 *sampleBuffer, int numFrames, float sampleRate, float frequency, float amp) {
    if(amp>1) amp=1;
    if(amp<0) amp=0;
    amp = amp * SHRT_MAX;
    
    float samplesPerCycle = sampleRate/frequency;
    for(int i = 0; i<numFrames; i++) {
        sampleBuffer[i] = (SInt16) amp * (2*(fmodf(sawIndex, samplesPerCycle)/samplesPerCycle)-1);
        sawIndex = sawIndex+1;
        if(sawIndex>=samplesPerCycle) sawIndex-=samplesPerCycle;
    }
}

int triIndex = 0;
void generateTriangle(SInt16 *sampleBuffer, int numFrames, float sampleRate, float frequency, float amp) {
    if(amp>1) amp=1;
    if(amp<0) amp=0;
    amp = amp * SHRT_MAX;
    
    float samplesPerCycle = sampleRate/frequency;
    for(int i = 0; i<numFrames; i++) {
        
        if(fmodf(triIndex, samplesPerCycle)/samplesPerCycle>0.5) {
            sampleBuffer[i] = (SInt16) amp * ((2-2*((fmodf(triIndex, samplesPerCycle)/samplesPerCycle-0.5)/0.5))-1);
        } else {
            sampleBuffer[i] = (SInt16) amp * ((2*((fmodf(triIndex, samplesPerCycle)/samplesPerCycle)/0.5))-1);
        }
        triIndex = triIndex+1;
    }
}

#pragma  mark - Audio Controller Delegate Methods -

float lastMeterValue = 0;
- (void) receivedAudioSamples:(SInt16 *)samples length:(int)len {
    //samples is an array of length n from the microphone. You don't need to free samples (the audio controller does that for you)
    
    float sum = 0;
    for (int i = 0; i<len ; i+=4) {
        sum += abs(samples[i]);
    }
    sum /= len;
    sum /= SHRT_MAX/25;
    
    sum +=1;
    
    float thisValue = (pow(10, sum)-10)/90;
    
    float finalValue = thisValue+0.99*lastMeterValue;
    lastMeterValue = finalValue;
    
    
    dispatch_async(dispatch_get_main_queue(), ^{
        audioMeter.amplitude = thisValue*thisValue;
    });
    
}

- (void) audioOutputNeedsSamples:(SInt16 *)sample length:(int)len {
    
    switch (waveControl.selectedSegmentIndex) {
        case 0:
            generateSine(sample, len, 44100, outputFrequency, outputAmplitude);
            break;
        case 1:
            generateSquare(sample, len, 44100, outputFrequency, outputAmplitude);
            break;
        case 2:
            generateTriangle(sample, len, 44100, outputFrequency, outputAmplitude);
            break;
        case 3:
            generateSawtooth(sample, len, 44100, outputFrequency, outputAmplitude);
            break;
            
        default:
            generateSine(sample, len, 44100, outputFrequency, outputAmplitude);
            break;
    }
}

#pragma mark - MIDI stuff - 
- (void) playNote {
    [[AudioController sharedAudioManager] playNote:44];
}

@end
