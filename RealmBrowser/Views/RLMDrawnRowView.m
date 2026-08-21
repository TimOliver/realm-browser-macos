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

@import CoreText;

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

+ (CGFloat)cellTextHeight
{
    static CGFloat height;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        height = ceil([@"Ag" sizeWithAttributes:@{NSFontAttributeName: [self cellTextFont]}].height);
    });
    return height;
}

+ (NSColor *)textColorForKind:(RLMCellContentKind)kind placeholder:(BOOL)placeholder emphasized:(BOOL)emphasized
{
    if (emphasized) {
        return NSColor.alternateSelectedControlTextColor;
    }
    if (placeholder) {
        return NSColor.placeholderTextColor;
    }
    if (kind == RLMCellContentKindLink) {
        return NSColor.linkColor;
    }
    return NSColor.labelColor;
}

// Laid-out lines, keyed by their text. Building a line is
// the expensive half of drawing a cell, and a table redraws the same values over and
// over — on scroll, on selection changes, on every navigation back to a class.
// The lines carry no colour (see kCTForegroundColorFromContextAttributeName below), so
// one cached line serves normal, link, placeholder and selected cells alike.
+ (NSCache<NSString *, id> *)lineCache
{
    static NSCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 4096;
    });
    return cache;
}

+ (NSDictionary *)lineAttributes
{
    static NSDictionary *attributes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        attributes = @{NSFontAttributeName: [self cellTextFont],
                       // Take the colour from the context at draw time, so one line can be
                       // shared between every colour a cell is drawn in.
                       (id)kCTForegroundColorFromContextAttributeName: @YES};
    });
    return attributes;
}

+ (CTLineRef)lineForText:(NSString *)text
{
    NSCache *cache = [self lineCache];
    id cached = [cache objectForKey:text];
    if (cached != nil) {
        return (__bridge CTLineRef)cached;
    }

    NSAttributedString *attributed = [[NSAttributedString alloc] initWithString:text attributes:[self lineAttributes]];
    CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)attributed);
    if (line == NULL) {
        return NULL;
    }
    [cache setObject:(__bridge_transfer id)line forKey:[text copy]];
    return (__bridge CTLineRef)[cache objectForKey:text];
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

#pragma mark - Layer behaviour

// A row's whole content changes whenever the table shows a different class, and a
// layer-backed view animates a contents change by default -- which reads as the table
// crossfading, and delays the frame by the length of the implicit animation.
- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event
{
    return (id<CAAction>)[NSNull null];
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
    if (NSWidth(rect) <= 0.0) {
        return;
    }
    CTLineRef line = [RLMDrawnRowView lineForText:text];
    if (line == NULL) {
        return;
    }

    // Only pay for a truncated line when the text actually overflows its column.
    CTLineRef lineToDraw = line;
    CTLineRef truncated = NULL;
    if (CTLineGetTypographicBounds(line, NULL, NULL, NULL) > NSWidth(rect)) {
        truncated = [RLMDrawnRowView truncatedLineFor:line width:NSWidth(rect)];
        if (truncated == NULL) {
            return;
        }
        lineToDraw = truncated;
    }

    CGFloat ascent = 0.0, descent = 0.0;
    CTLineGetTypographicBounds(lineToDraw, &ascent, &descent, NULL);
    CGFloat baseline = round(NSMidY(rect) + (ascent - descent) / 2.0);

    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(context);
    // The row view is flipped, so the glyphs are flipped back the other way and the
    // baseline is measured from the top of the view like every other rect here.
    CGContextSetTextMatrix(context, CGAffineTransformMakeScale(1.0, -1.0));
    CGContextSetFillColorWithColor(context, [RLMDrawnRowView textColorForKind:kind placeholder:placeholder emphasized:emphasized].CGColor);
    CGContextSetTextPosition(context, NSMinX(rect), baseline);
    CTLineDraw(lineToDraw, context);
    CGContextRestoreGState(context);

    if (truncated != NULL) {
        CFRelease(truncated);
    }
}

// Caller owns the returned line. NULL when not even the ellipsis fits.
+ (CTLineRef)truncatedLineFor:(CTLineRef)line width:(CGFloat)width
{
    static CTLineRef token;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSAttributedString *ellipsis = [[NSAttributedString alloc] initWithString:@"\u2026"
                                                                       attributes:[self lineAttributes]];
        token = CTLineCreateWithAttributedString((CFAttributedStringRef)ellipsis);
    });
    return CTLineCreateTruncatedLine(line, width, kCTLineTruncationEnd, token);
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

#pragma mark - Dragging

// With no cell views the default drag image would be empty; snapshot the row instead.
- (NSArray<NSDraggingImageComponent *> *)draggingImageComponents
{
    NSRect bounds = self.bounds;
    NSBitmapImageRep *rep = [self bitmapImageRepForCachingDisplayInRect:bounds];
    [self cacheDisplayInRect:bounds toBitmapImageRep:rep];
    NSImage *image = [[NSImage alloc] initWithSize:bounds.size];
    [image addRepresentation:rep];

    NSDraggingImageComponent *component = [NSDraggingImageComponent draggingImageComponentWithKey:NSDraggingImageComponentIconKey];
    component.contents = image;
    component.frame = bounds;
    return @[component];
}

#pragma mark - Accessibility

// Expose one element per visible column so VoiceOver can still navigate cells.
- (NSArray *)accessibilityChildren
{
    NSTableView *tableView = self.tableView;
    id<RLMDrawnRowViewDataSource> dataSource = self.contentDataSource;
    NSInteger row = (tableView != nil) ? [tableView rowForView:self] : -1;
    if (dataSource == nil || row < 0) {
        return @[];
    }

    NSMutableArray *children = [NSMutableArray array];
    NSArray<NSTableColumn *> *columns = tableView.tableColumns;
    for (NSUInteger columnIndex = 0; columnIndex < columns.count; columnIndex++) {
        NSTableColumn *column = columns[columnIndex];
        if (column.hidden) {
            continue;
        }
        NSRect cellRect = [self convertRect:[tableView frameOfCellAtColumn:(NSInteger)columnIndex row:row] fromView:tableView];
        RLMCellContent *content = [dataSource rowView:self contentForTableColumn:column row:row];
        // The convenience constructor's frame is in screen coordinates; the cell rect is
        // row-local, so it is handed over as the parent-space frame instead and AppKit
        // converts it (and keeps converting it when the window moves).
        NSAccessibilityElement *element = [NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityCellRole
                                                                                        frame:NSZeroRect
                                                                                        label:column.title
                                                                                       parent:self];
        element.accessibilityFrameInParentSpace = cellRect;
        element.accessibilityValue = [content accessibilityValueString] ?: @"";
        [children addObject:element];
    }
    return children;
}

@end
