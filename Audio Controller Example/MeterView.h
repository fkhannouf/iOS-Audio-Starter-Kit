//
//  MeterView.h
//  Audio Controller Example
//
//  Created by Kevin Murphy on 2/10/13.
//  Copyright (c) 2013 Kevin Murphy. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface MeterView : UIView
{
    UIView *amplitudeRect;
}
@property (nonatomic, readwrite) float amplitude;
@end
