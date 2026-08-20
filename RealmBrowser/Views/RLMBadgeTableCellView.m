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

#import "RLMBadgeTableCellView.h"

@implementation RLMBadgeTableCellView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    
    if (self == nil) {
        return nil;
    }

    // Frame-based layout: see RLMBasicTableCellView. This cell manages the
    // inherited text field's frame itself, so it must not autoresize to fill.
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.buttonType = NSButtonTypeMomentaryPushIn;
    button.bezelStyle = NSBezelStyleInline;

    if ([button respondsToSelector:@selector(setLineBreakMode:)]) {
        button.lineBreakMode = NSLineBreakByTruncatingTail;
    }

    self.badge = button;
    [self addSubview:button];

    self.textField.autoresizingMask = NSViewNotSizable;

    return self;
}

- (void)layout
{
    [super layout];

    // The badge hugs the trailing edge at its natural size (which tracks its
    // title, so the controller marks the cell needsLayout after changing it);
    // the text field fills the rest.
    [self.badge sizeToFit];

    NSRect bounds = self.bounds;
    NSSize badgeSize = self.badge.frame.size;
    self.badge.frame = NSMakeRect(NSMaxX(bounds) - badgeSize.width,
                                  round(NSMidY(bounds) - (badgeSize.height / 2.0)),
                                  badgeSize.width, badgeSize.height);
    self.textField.frame = NSMakeRect(0.0, 0.0,
                                      MAX(0.0, bounds.size.width - badgeSize.width - 4.0),
                                      bounds.size.height);
}

@end
