//
//  ViewController.h
//  Audio Controller Example
//
//  Created by Kevin Murphy on 2/9/13.
//  Copyright (c) 2013 Kevin Murphy. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AudioController.h"
#import "MeterView.h"

@interface ViewController : UIViewController <AudioManagerDelegate>
{
    float outputFrequency, outputAmplitude;
    UISegmentedControl *waveControl;
    MeterView *audioMeter;
}
@end
