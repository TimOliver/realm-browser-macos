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

#import "RLMBasicTableCellView.h"

@implementation RLMBasicTableCellView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    
    if (self == nil) {
        return nil;
    }
    
    // Cells are created by the hundreds while scrolling/navigating, so they are
    // laid out manually in -layout — constraint setup and solving dominated the
    // profile when populating rows. translatesAutoresizingMaskIntoConstraints is
    // disabled WITHOUT adding constraints so that no constraints exist for these
    // views at all; NSTableCellView's automatic textField placement otherwise
    // fights the autoresizing-mask constraints and floods the console.
    NSTextField *textField = [[NSTextField alloc] initWithFrame:self.bounds];
    textField.translatesAutoresizingMaskIntoConstraints = NO;
    textField.bordered = NO;
    textField.drawsBackground = NO;
    textField.cell.sendsActionOnEndEditing = YES;

    if ([NSFont respondsToSelector:@selector(monospacedDigitSystemFontOfSize:weight:)]) {
        textField.font = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightRegular];
    }
    
    if ([textField respondsToSelector:@selector(setLineBreakMode:)]) {
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
    }
        
    self.textField = textField;
    [self addSubview:textField];

    return self;
}

- (void)layout
{
    [super layout];
    self.textField.frame = self.bounds;
}

@end
