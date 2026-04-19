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

#import "RLMWelcomeRecentsCellView.h"

@interface RLMWelcomeRecentsCellView ()
@property (nonatomic, strong, readwrite) NSImageView *iconView;
@property (nonatomic, strong, readwrite) NSTextField *titleLabel;
@property (nonatomic, strong, readwrite) NSTextField *subtitleLabel;
@end

@implementation RLMWelcomeRecentsCellView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (!self) { return nil; }

    self.iconView = [[NSImageView alloc] init];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.imageScaling = NSImageScaleProportionallyDown;
    [self addSubview:self.iconView];

    self.titleLabel = [NSTextField labelWithString:@""];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:self.titleLabel];

    self.subtitleLabel = [NSTextField labelWithString:@""];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
    self.subtitleLabel.textColor = [NSColor secondaryLabelColor];
    self.subtitleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self addSubview:self.subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12.0],
        [self.iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.iconView.widthAnchor constraintEqualToConstant:32.0],
        [self.iconView.heightAnchor constraintEqualToConstant:32.0],

        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconView.trailingAnchor constant:8.0],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12.0],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.iconView.topAnchor constant:-1.0],

        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:2.0],
    ]];

    return self;
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
    [super setBackgroundStyle:backgroundStyle];
    BOOL emphasized = backgroundStyle == NSBackgroundStyleEmphasized;
    self.titleLabel.textColor = emphasized ? [NSColor alternateSelectedControlTextColor] : [NSColor labelColor];
    self.subtitleLabel.textColor = emphasized ? [NSColor alternateSelectedControlTextColor] : [NSColor secondaryLabelColor];
}

@end
