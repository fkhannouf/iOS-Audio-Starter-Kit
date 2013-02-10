//
//  MeterView.m
//  Audio Controller Example
//
//  Created by Kevin Murphy on 2/10/13.
//  Copyright (c) 2013 Kevin Murphy. All rights reserved.
//

#import "MeterView.h"

@implementation MeterView
@synthesize amplitude;

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        amplitudeRect = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 15, self.bounds.size.height)];
        amplitudeRect.backgroundColor = [UIColor whiteColor];
        [self addSubview:amplitudeRect];
        self.backgroundColor = [UIColor blueColor];
        // Initialization code
    }
    return self;
}

- (void) setAmplitude:(float)newAmplitude {
    amplitude = newAmplitude;
    amplitudeRect.frame = CGRectMake(0, 0, self.bounds.size.width*newAmplitude, self.bounds.size.height);
    printf("%f\n", amplitudeRect.frame.size.width);
}


@end
