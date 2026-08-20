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

#import "RLMTableCellView.h"

@implementation RLMTableCellView

+ (instancetype)viewWithIdentifier:(NSString *)identifier
{
    RLMTableCellView *view = [[self alloc] initWithFrame:NSZeroRect];
    view.identifier = identifier;

    return view;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    if (self = [super initWithFrame:frameRect]) {
        self.canDrawSubviewsIntoLayer = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
    }

    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (self = [super initWithCoder:coder]) {
        self.canDrawSubviewsIntoLayer = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
    }

    return self;
}

#pragma mark - Drawn text

// Text cells draw their string directly rather than hosting an NSTextField —
// the field's cell machinery, field-editor readiness, and text layer dominated
// the profile when populating and scrolling rows. Editing goes through the
// controller's shared overlay editor instead.

+ (NSFont *)cellTextFont
{
    static NSFont *font;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        font = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightRegular];
    });
    return font;
}

+ (NSParagraphStyle *)cellTextParagraphStyle
{
    static NSParagraphStyle *style;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableParagraphStyle *mutableStyle = [[NSMutableParagraphStyle alloc] init];
        mutableStyle.lineBreakMode = NSLineBreakByTruncatingTail;
        style = [mutableStyle copy];
    });
    return style;
}

+ (CGFloat)cellTextHeight
{
    static CGFloat height;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        height = ceil([@"Ag" sizeWithAttributes:@{NSFontAttributeName: [self cellTextFont]}].height);
    });
    return height;
}

- (void)setText:(NSString *)text
{
    if (text == _text || [text isEqualToString:_text]) {
        return;
    }
    _text = [text copy];
    [self setNeedsDisplay:YES];
}

- (void)setOptional:(BOOL)optional
{
    if (optional == _optional) {
        return;
    }
    _optional = optional;
    [self setNeedsDisplay:YES];
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
    [super setBackgroundStyle:backgroundStyle];
    [self setNeedsDisplay:YES];
}

- (NSDictionary *)textAttributes
{
    NSColor *color = (self.backgroundStyle == NSBackgroundStyleEmphasized) ? NSColor.alternateSelectedControlTextColor
                                                                           : NSColor.labelColor;
    return @{NSFontAttributeName: [RLMTableCellView cellTextFont],
             NSParagraphStyleAttributeName: [RLMTableCellView cellTextParagraphStyle],
             NSForegroundColorAttributeName: color};
}

- (NSDictionary *)placeholderTextAttributes
{
    NSColor *color = (self.backgroundStyle == NSBackgroundStyleEmphasized) ? NSColor.alternateSelectedControlTextColor
                                                                           : NSColor.placeholderTextColor;
    return @{NSFontAttributeName: [RLMTableCellView cellTextFont],
             NSParagraphStyleAttributeName: [RLMTableCellView cellTextParagraphStyle],
             NSForegroundColorAttributeName: color};
}

- (NSRect)textDrawingRect
{
    return self.bounds;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];

    NSString *text = self.text;
    if (text == nil) {
        return;
    }

    NSDictionary *attributes;
    if (text.length == 0) {
        if (!self.optional) {
            return;
        }
        text = @"nil";
        attributes = [self placeholderTextAttributes];
    }
    else {
        attributes = [self textAttributes];
    }

    NSRect rect = [self textDrawingRect];
    CGFloat height = [RLMTableCellView cellTextHeight];
    rect = NSMakeRect(NSMinX(rect), round(NSMidY(rect) - (height / 2.0)), NSWidth(rect), height);
    [text drawInRect:rect withAttributes:attributes];
}

@end
