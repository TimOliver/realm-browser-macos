////////////////////////////////////////////////////////////////////////////
//
// Copyright 2026 Realm Browser Contributors
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

#import "RLMWelcomeActionButton.h"

static const CGFloat kCornerRadius = 8.0;
static const CGFloat kHorizontalInset = 8.0;
static const CGFloat kIconTitleSpacing = 8.0;
static const CGFloat kSymbolPointSize = 16.0;
static const CGFloat kTitleFontSize = 13.0;

@implementation RLMWelcomeActionButton

- (instancetype)initWithTitle:(NSString *)title symbolName:(NSString *)symbolName
{
    self = [super initWithFrame:NSZeroRect];
    if (!self) { return nil; }

    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;
    self.bordered = NO;
    self.bezelStyle = NSBezelStyleRegularSquare;
    self.title = @"";
    self.layer.cornerRadius = kCornerRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;

    NSImageView *iconView = [[NSImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.imageScaling = NSImageScaleProportionallyDown;
    if (@available(macOS 10.14, *)) {
        iconView.contentTintColor = [NSColor secondaryLabelColor];
    }
    if (@available(macOS 11.0, *)) {
        if (symbolName) {
            NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:kSymbolPointSize
                                                                                                  weight:NSFontWeightSemibold];
            NSImage *symbol = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
            iconView.image = [symbol imageWithSymbolConfiguration:config];
        }
    }
    [self addSubview:iconView];

    NSTextField *titleLabel = [NSTextField labelWithString:title];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.selectable = NO;
    titleLabel.font = [NSFont systemFontOfSize:kTitleFontSize weight:NSFontWeightSemibold];
    titleLabel.textColor = [NSColor labelColor];
    [self addSubview:titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:kHorizontalInset],
        [iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [titleLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:kIconTitleSpacing],
        [titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-kHorizontalInset],
    ]];

    return self;
}

// Route all clicks within our bounds to the button itself so the NSImageView and
// NSTextField subviews never swallow them.
- (NSView *)hitTest:(NSPoint)point
{
    if (!self.hidden && [self.superview mouse:point inRect:self.frame]) {
        return self;
    }
    return nil;
}

- (BOOL)wantsUpdateLayer { return YES; }

- (void)updateLayer
{
    NSAppearanceName matched = [self.effectiveAppearance bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAqua, NSAppearanceNameDarkAqua,
        NSAppearanceNameVibrantLight, NSAppearanceNameVibrantDark,
    ]];
    BOOL isDark = [matched isEqualToString:NSAppearanceNameDarkAqua]
               || [matched isEqualToString:NSAppearanceNameVibrantDark];
    CGFloat base = isDark ? 0.08 : 0.05;
    CGFloat alpha = self.isHighlighted ? base * 1.8 : base;
    NSColor *color = isDark
        ? [NSColor colorWithWhite:1.0 alpha:alpha]
        : [NSColor colorWithWhite:0.0 alpha:alpha];
    self.layer.backgroundColor = color.CGColor;
}

- (void)setHighlighted:(BOOL)flag
{
    [super setHighlighted:flag];
    [self updateLayer];
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    [self updateLayer];
}

@end
