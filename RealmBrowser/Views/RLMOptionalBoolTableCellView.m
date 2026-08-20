////////////////////////////////////////////////////////////////////////////
//
// Copyright 2014-2015 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

#import "RLMOptionalBoolTableCellView.h"
#import "RLMBrowserConstants.h"
#import "NSColor+ByteSizeFactory.h"

@interface RLMOptionalBoolTableCellView ()

@property (nonatomic, strong, readwrite) NSPopUpButton *popupControl;

@end

@implementation RLMOptionalBoolTableCellView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    
    if (self == nil) {
        return nil;
    }
    
    // Manual frame layout: see RLMBasicTableCellView.
    NSPopUpButton *popupButton = [[NSPopUpButton alloc] initWithFrame:self.bounds pullsDown:NO];
    popupButton.translatesAutoresizingMaskIntoConstraints = NO;
    [popupButton addItemsWithTitles:@[@"nil", @"false", @"true"]];
    popupButton.bordered = NO;
    [popupButton sizeToFit];
    self.popupControl = popupButton;
    [self addSubview:popupButton];

    return self;
}

- (void)layout
{
    [super layout];

    NSRect bounds = self.bounds;
    NSSize size = self.popupControl.frame.size;
    self.popupControl.frame = NSMakeRect(0.0,
                                         round(NSMidY(bounds) - (size.height / 2.0)),
                                         MIN(size.width, bounds.size.width), size.height);
}

@end
