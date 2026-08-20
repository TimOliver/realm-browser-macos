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

#import "RLMNumberTableCellView.h"

@interface RLMNumberTextField : NSTextField

@end

@implementation RLMNumberTextField

// Creating an NSNumberFormatter is expensive (it performs ICU locale setup), so
// all number fields share two immutable instances rather than building their own.
+ (NSNumberFormatter *)displayFormatter {
    static NSNumberFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        formatter.maximumFractionDigits = UINT16_MAX;
    });
    return formatter;
}

+ (NSNumberFormatter *)editingFormatter {
    static NSNumberFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        formatter.maximumFractionDigits = UINT16_MAX;
        formatter.hasThousandSeparators = NO;
    });
    return formatter;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if (self = [super initWithFrame:frameRect]) {
        self.formatter = [RLMNumberTextField displayFormatter];
    }

    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder:coder]) {
        self.formatter = [RLMNumberTextField displayFormatter];
    }

    return self;
}

-(BOOL)becomeFirstResponder {
    self.formatter = [RLMNumberTextField editingFormatter];

    return [super becomeFirstResponder];
}

- (BOOL)resignFirstResponder {
    self.formatter = [RLMNumberTextField displayFormatter];

    return [super resignFirstResponder];
}

@end

@implementation RLMNumberTableCellView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    
    if (self == nil) {
        return nil;
    }
    
    // Frame-based layout: see RLMBasicTableCellView.
    RLMNumberTextField *textField = [[RLMNumberTextField alloc] initWithFrame:self.bounds];
    textField.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    textField.bordered = NO;
    textField.drawsBackground = NO;
    textField.alignment = NSTextAlignmentLeft;
    textField.cell.sendsActionOnEndEditing = YES;
    
    if ([NSFont respondsToSelector:@selector(monospacedDigitSystemFontOfSize:weight:)]) {
        textField.font = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightRegular];
    }

    if ([textField respondsToSelector:@selector(setUsesSingleLineMode:)]) {
        textField.usesSingleLineMode = YES;
    }
    
    if ([textField respondsToSelector:@selector(setLineBreakMode:)]) {
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    
    self.textField = textField;
    [self addSubview:textField];

    return self;
}

@end

