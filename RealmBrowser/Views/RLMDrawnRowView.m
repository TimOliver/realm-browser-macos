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

#import "RLMDrawnRowView.h"
#import "RLMCellContent.h"

NSString * const RLMDrawnRowViewReuseIdentifier = @"RLMDrawnRowView";

static const CGFloat kCheckboxSide = 12.0;
static const CGFloat kBadgeHeight = 16.0;
static const CGFloat kBadgeHorizontalPadding = 6.0;
static const CGFloat kBadgeGap = 4.0;

@implementation RLMDrawnRowView

#pragma mark - Shared text style

+ (NSFont *)cellTextFont
{
    static NSFont *font;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        font = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightRegular];
    });
    return font;
}

+ (NSFont *)badgeFont
{
    static NSFont *font;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightSemibold];
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

// Text attributes for the three text styles, normal and emphasized (selected row).
+ (NSDictionary *)attributesForKind:(RLMCellContentKind)kind placeholder:(BOOL)placeholder emphasized:(BOOL)emphasized
{
    NSColor *color;
    if (emphasized) {
        color = NSColor.alternateSelectedControlTextColor;
    }
    else if (placeholder) {
        color = NSColor.placeholderTextColor;
    }
    else if (kind == RLMCellContentKindLink) {
        color = NSColor.linkColor;
    }
    else {
        color = NSColor.labelColor;
    }

    NSMutableDictionary *attributes = [@{NSFontAttributeName: [self cellTextFont],
                                         NSParagraphStyleAttributeName: [self cellTextParagraphStyle],
                                         NSForegroundColorAttributeName: color} mutableCopy];
    if (kind == RLMCellContentKindLink && !placeholder) {
        attributes[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
    }
    return attributes;
}

#pragma mark - Redraw on selection changes

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    [self setNeedsDisplay:YES];
}

- (void)setEmphasized:(BOOL)emphasized
{
    [super setEmphasized:emphasized];
    [self setNeedsDisplay:YES];
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect]; // background, selection, separators

    NSTableView *tableView = self.tableView;
    id<RLMDrawnRowViewDataSource> dataSource = self.contentDataSource;
    if (tableView == nil || dataSource == nil) {
        return;
    }
    // Row views move when rows are inserted or removed, so the row is looked up live.
    NSInteger row = [tableView rowForView:self];
    if (row < 0) {
        return;
    }

    BOOL emphasized = (self.interiorBackgroundStyle == NSBackgroundStyleEmphasized);
    NSArray<NSTableColumn *> *columns = tableView.tableColumns;
    for (NSUInteger columnIndex = 0; columnIndex < columns.count; columnIndex++) {
        NSTableColumn *column = columns[columnIndex];
        if (column.hidden) {
            continue;
        }
        NSRect cellRect = [self convertRect:[tableView frameOfCellAtColumn:(NSInteger)columnIndex row:row] fromView:tableView];
        if (!NSIntersectsRect(cellRect, dirtyRect)) {
            continue;
        }
        RLMCellContent *content = [dataSource rowView:self contentForTableColumn:column row:row];
        if (content != nil) {
            [self drawContent:content inRect:cellRect emphasized:emphasized];
        }
    }
}

- (void)drawContent:(RLMCellContent *)content inRect:(NSRect)cellRect emphasized:(BOOL)emphasized
{
    switch (content.kind) {
        case RLMCellContentKindBool:
            [self drawCheckboxChecked:content.boolValue inRect:cellRect emphasized:emphasized];
            return;

        case RLMCellContentKindBadge: {
            CGFloat badgeWidth = [self drawBadge:content.badgeText inRect:cellRect emphasized:emphasized];
            NSRect textRect = cellRect;
            textRect.size.width = MAX(0.0, NSWidth(cellRect) - badgeWidth - kBadgeGap);
            [self drawText:content.text kind:RLMCellContentKindLink placeholder:NO inRect:textRect emphasized:emphasized];
            return;
        }

        case RLMCellContentKindText:
        case RLMCellContentKindLink: {
            NSString *text = content.text;
            BOOL placeholder = NO;
            if (text.length == 0) {
                if (!content.showsNilPlaceholder) {
                    return;
                }
                text = @"nil";
                placeholder = YES;
            }
            [self drawText:text kind:content.kind placeholder:placeholder inRect:cellRect emphasized:emphasized];
            return;
        }
    }
}

- (void)drawText:(NSString *)text kind:(RLMCellContentKind)kind placeholder:(BOOL)placeholder inRect:(NSRect)rect emphasized:(BOOL)emphasized
{
    CGFloat height = [RLMDrawnRowView cellTextHeight];
    NSRect textRect = NSMakeRect(NSMinX(rect), round(NSMidY(rect) - height / 2.0), NSWidth(rect), height);
    [text drawInRect:textRect withAttributes:[RLMDrawnRowView attributesForKind:kind placeholder:placeholder emphasized:emphasized]];
}

- (void)drawCheckboxChecked:(BOOL)checked inRect:(NSRect)cellRect emphasized:(BOOL)emphasized
{
    NSRect box = NSMakeRect(round(NSMidX(cellRect) - kCheckboxSide / 2.0) + 0.5,
                            round(NSMidY(cellRect) - kCheckboxSide / 2.0) + 0.5,
                            kCheckboxSide, kCheckboxSide);
    NSColor *frameColor = emphasized ? NSColor.alternateSelectedControlTextColor : NSColor.tertiaryLabelColor;
    NSColor *checkColor = emphasized ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor;

    NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:box xRadius:3.0 yRadius:3.0];
    border.lineWidth = 1.0;
    [frameColor setStroke];
    [border stroke];

    if (checked) {
        NSBezierPath *check = [NSBezierPath bezierPath];
        check.lineWidth = 1.5;
        check.lineCapStyle = NSLineCapStyleRound;
        check.lineJoinStyle = NSLineJoinStyleRound;
        // Flipped coordinates (NSTableRowView is flipped): y grows downwards.
        [check moveToPoint:NSMakePoint(NSMinX(box) + 3.0, NSMinY(box) + 6.5)];
        [check lineToPoint:NSMakePoint(NSMinX(box) + 5.5, NSMinY(box) + 9.0)];
        [check lineToPoint:NSMakePoint(NSMinX(box) + 9.5, NSMinY(box) + 3.5)];
        [checkColor setStroke];
        [check stroke];
    }
}

// Draws the count pill hugging the trailing edge and returns its width.
- (CGFloat)drawBadge:(NSString *)badgeText inRect:(NSRect)cellRect emphasized:(BOOL)emphasized
{
    NSColor *textColor = emphasized ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor;
    NSColor *fillColor = emphasized ? [NSColor.alternateSelectedControlTextColor colorWithAlphaComponent:0.3]
                                    : [NSColor.labelColor colorWithAlphaComponent:0.12];
    NSDictionary *attributes = @{NSFontAttributeName: [RLMDrawnRowView badgeFont], NSForegroundColorAttributeName: textColor};
    NSSize textSize = [badgeText sizeWithAttributes:attributes];
    CGFloat width = ceil(textSize.width) + 2.0 * kBadgeHorizontalPadding;
    NSRect pill = NSMakeRect(NSMaxX(cellRect) - width, round(NSMidY(cellRect) - kBadgeHeight / 2.0), width, kBadgeHeight);

    [fillColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:pill xRadius:kBadgeHeight / 2.0 yRadius:kBadgeHeight / 2.0] fill];
    NSRect textRect = NSMakeRect(NSMinX(pill) + kBadgeHorizontalPadding, round(NSMidY(pill) - textSize.height / 2.0), ceil(textSize.width), ceil(textSize.height));
    [badgeText drawInRect:textRect withAttributes:attributes];
    return width;
}

@end
