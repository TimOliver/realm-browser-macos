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

#import "RLMWelcomeWindowController.h"
#import "RLMBrowserConstants.h"
#import "RLMTestDataGenerator.h"
#import "TestClasses.h"

static const CGFloat kWelcomeWindowWidth = 750.0;
static const CGFloat kWelcomeWindowHeight = 460.0;
static const CGFloat kRightPaneWidth = 280.0;
static const CGFloat kAppIconSize = 130.0;
static const CGFloat kActionButtonWidth = 350.0;
static const CGFloat kActionButtonHeight = 36.0;
static const CGFloat kRecentsRowHeight = 44.0;

@interface RLMWelcomeRecentsCellView : NSTableCellView
@property (nonatomic, strong) NSImageView *iconView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *subtitleLabel;
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
    self.titleLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:self.titleLabel];

    self.subtitleLabel = [NSTextField labelWithString:@""];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular];
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

@end

@interface RLMWelcomeWindowController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSTableView *recentsTableView;
@property (nonatomic, strong) NSTextField *recentsEmptyLabel;
@property (nonatomic, copy) NSArray<NSURL *> *recentURLs;

@end

@implementation RLMWelcomeWindowController

+ (instancetype)sharedController
{
    static RLMWelcomeWindowController *sharedController = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedController = [[RLMWelcomeWindowController alloc] init];
    });
    return sharedController;
}

- (instancetype)init
{
    NSRect contentRect = NSMakeRect(0, 0, kWelcomeWindowWidth, kWelcomeWindowHeight);
    NSWindowStyleMask styleMask = NSWindowStyleMaskTitled
                                | NSWindowStyleMaskClosable
                                | NSWindowStyleMaskFullSizeContentView;

    NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect
                                                   styleMask:styleMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.titlebarAppearsTransparent = YES;
    window.titleVisibility = NSWindowTitleHidden;
    window.movableByWindowBackground = YES;
    window.restorable = NO;
    window.releasedWhenClosed = NO;
    [window standardWindowButton:NSWindowZoomButton].hidden = YES;
    [window standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;

    self = [super initWithWindow:window];
    if (!self) { return nil; }

    [self buildContent];
    [self reloadRecentDocuments];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadRecentDocuments)
                                                 name:NSApplicationDidBecomeActiveNotification
                                               object:nil];

    return self;
}

- (void)buildContent
{
    NSView *contentView = self.window.contentView;

    // Left pane (default material).
    NSView *leftPane = [[NSView alloc] init];
    leftPane.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:leftPane];

    // Right pane (sidebar blur).
    NSVisualEffectView *rightPane = [[NSVisualEffectView alloc] init];
    rightPane.translatesAutoresizingMaskIntoConstraints = NO;
    rightPane.material = NSVisualEffectMaterialSidebar;
    rightPane.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    rightPane.state = NSVisualEffectStateActive;
    [contentView addSubview:rightPane];

    [NSLayoutConstraint activateConstraints:@[
        [leftPane.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [leftPane.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [leftPane.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [leftPane.trailingAnchor constraintEqualToAnchor:rightPane.leadingAnchor],

        [rightPane.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [rightPane.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [rightPane.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [rightPane.widthAnchor constraintEqualToConstant:kRightPaneWidth],
    ]];

    [self populateLeftPane:leftPane];
    [self populateRightPane:rightPane];
}

- (void)populateLeftPane:(NSView *)leftPane
{
    NSImageView *iconView = [[NSImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.image = [NSApp applicationIconImage];
    iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [leftPane addSubview:iconView];

    NSTextField *titleLabel = [NSTextField labelWithString:@"Realm Browser"];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont systemFontOfSize:32.0 weight:NSFontWeightBold];
    titleLabel.textColor = [NSColor labelColor];
    titleLabel.alignment = NSTextAlignmentCenter;
    [leftPane addSubview:titleLabel];

    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSTextField *versionLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"Version %@", version]];
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    versionLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
    versionLabel.textColor = [NSColor secondaryLabelColor];
    versionLabel.alignment = NSTextAlignmentCenter;
    [leftPane addSubview:versionLabel];

    NSButton *openButton = [self actionButtonWithTitle:@"Open Existing Realm\u2026"
                                            symbolName:@"folder"
                                                action:@selector(openExistingRealm:)];
    [leftPane addSubview:openButton];

    NSButton *createButton = [self actionButtonWithTitle:@"Create Test Realm\u2026"
                                              symbolName:@"doc.badge.plus"
                                                  action:@selector(createTestRealm:)];
    [leftPane addSubview:createButton];

    [NSLayoutConstraint activateConstraints:@[
        [iconView.centerXAnchor constraintEqualToAnchor:leftPane.centerXAnchor],
        [iconView.topAnchor constraintEqualToAnchor:leftPane.topAnchor constant:60.0],
        [iconView.widthAnchor constraintEqualToConstant:kAppIconSize],
        [iconView.heightAnchor constraintEqualToConstant:kAppIconSize],

        [titleLabel.centerXAnchor constraintEqualToAnchor:leftPane.centerXAnchor],
        [titleLabel.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:12.0],

        [versionLabel.centerXAnchor constraintEqualToAnchor:leftPane.centerXAnchor],
        [versionLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4.0],

        [openButton.centerXAnchor constraintEqualToAnchor:leftPane.centerXAnchor],
        [openButton.topAnchor constraintEqualToAnchor:versionLabel.bottomAnchor constant:36.0],
        [openButton.widthAnchor constraintEqualToConstant:kActionButtonWidth],
        [openButton.heightAnchor constraintEqualToConstant:kActionButtonHeight],

        [createButton.centerXAnchor constraintEqualToAnchor:leftPane.centerXAnchor],
        [createButton.topAnchor constraintEqualToAnchor:openButton.bottomAnchor constant:10.0],
        [createButton.widthAnchor constraintEqualToConstant:kActionButtonWidth],
        [createButton.heightAnchor constraintEqualToConstant:kActionButtonHeight],
    ]];
}

- (NSButton *)actionButtonWithTitle:(NSString *)title symbolName:(NSString *)symbolName action:(SEL)action
{
    NSButton *button = [[NSButton alloc] init];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStyleRegularSquare;
    button.bordered = YES;
    button.target = self;
    button.action = action;

    if (@available(macOS 11.0, *)) {
        button.bezelStyle = NSBezelStyleRegularSquare;
    }

    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] init];

    NSImage *symbol = nil;
    if (@available(macOS 11.0, *)) {
        symbol = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
    }
    if (symbol) {
        NSImage *tinted = [symbol copy];
        if (@available(macOS 11.0, *)) {
            NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:15.0
                                                                                                  weight:NSFontWeightRegular];
            tinted = [symbol imageWithSymbolConfiguration:config];
        }
        NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
        NSImage *tintedImage = tinted;
        if (@available(macOS 11.0, *)) {
            NSImage *colored = [NSImage imageWithSize:tinted.size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
                [[NSColor secondaryLabelColor] set];
                NSRectFill(dstRect);
                [tinted drawInRect:dstRect fromRect:NSZeroRect operation:NSCompositingOperationDestinationIn fraction:1.0];
                return YES;
            }];
            colored.template = NO;
            tintedImage = colored;
        }
        attachment.image = tintedImage;
        NSAttributedString *imageString = [NSAttributedString attributedStringWithAttachment:attachment];
        [attributed appendAttributedString:imageString];
        [attributed appendAttributedString:[[NSAttributedString alloc] initWithString:@"  "]];
    }

    NSDictionary *titleAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor labelColor],
    };
    [attributed appendAttributedString:[[NSAttributedString alloc] initWithString:title attributes:titleAttrs]];

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    [attributed addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, attributed.length)];

    button.attributedTitle = attributed;

    return button;
}

- (void)populateRightPane:(NSView *)rightPane
{
    NSScrollView *scrollView = [[NSScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.drawsBackground = NO;
    scrollView.borderType = NSNoBorder;
    scrollView.hasVerticalScroller = YES;
    scrollView.automaticallyAdjustsContentInsets = NO;
    [rightPane addSubview:scrollView];

    NSTableView *tableView = [[NSTableView alloc] init];
    tableView.headerView = nil;
    tableView.backgroundColor = [NSColor clearColor];
    tableView.rowHeight = kRecentsRowHeight;
    tableView.intercellSpacing = NSMakeSize(0.0, 0.0);
    tableView.gridStyleMask = NSTableViewGridNone;
    tableView.allowsEmptySelection = YES;
    tableView.allowsMultipleSelection = NO;
    tableView.style = NSTableViewStylePlain;
    tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    tableView.focusRingType = NSFocusRingTypeNone;
    tableView.target = self;
    tableView.doubleAction = @selector(recentDoubleClicked:);
    tableView.dataSource = self;
    tableView.delegate = self;

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"recent"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [tableView addTableColumn:column];

    scrollView.documentView = tableView;
    self.recentsTableView = tableView;

    self.recentsEmptyLabel = [NSTextField labelWithString:@"No Recent Realms"];
    self.recentsEmptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.recentsEmptyLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
    self.recentsEmptyLabel.textColor = [NSColor secondaryLabelColor];
    self.recentsEmptyLabel.alignment = NSTextAlignmentCenter;
    self.recentsEmptyLabel.hidden = YES;
    [rightPane addSubview:self.recentsEmptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:rightPane.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:rightPane.bottomAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:rightPane.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:rightPane.trailingAnchor],

        [self.recentsEmptyLabel.centerXAnchor constraintEqualToAnchor:rightPane.centerXAnchor],
        [self.recentsEmptyLabel.centerYAnchor constraintEqualToAnchor:rightPane.centerYAnchor],
    ]];
}

#pragma mark - Public

- (void)showWelcomeWindow
{
    [self reloadRecentDocuments];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
}

#pragma mark - Recents

- (void)reloadRecentDocuments
{
    self.recentURLs = [[NSDocumentController sharedDocumentController] recentDocumentURLs] ?: @[];
    self.recentsEmptyLabel.hidden = self.recentURLs.count > 0;
    self.recentsTableView.hidden = self.recentURLs.count == 0;
    [self.recentsTableView reloadData];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return self.recentURLs.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    static NSString *const kIdentifier = @"RecentCell";
    RLMWelcomeRecentsCellView *cell = [tableView makeViewWithIdentifier:kIdentifier owner:self];
    if (!cell) {
        cell = [[RLMWelcomeRecentsCellView alloc] initWithFrame:NSMakeRect(0, 0, kRightPaneWidth, kRecentsRowHeight)];
        cell.identifier = kIdentifier;
    }

    NSURL *url = self.recentURLs[row];
    cell.iconView.image = [[NSWorkspace sharedWorkspace] iconForFile:url.path];
    cell.titleLabel.stringValue = url.lastPathComponent ?: @"";

    NSString *parentPath = [url.path stringByDeletingLastPathComponent];
    NSString *abbreviated = [parentPath stringByAbbreviatingWithTildeInPath] ?: parentPath ?: @"";
    cell.subtitleLabel.stringValue = abbreviated;

    return cell;
}

#pragma mark - Actions

- (void)recentDoubleClicked:(id)sender
{
    NSInteger row = self.recentsTableView.clickedRow;
    if (row < 0 || row >= (NSInteger)self.recentURLs.count) { return; }

    NSURL *url = self.recentURLs[row];
    [self openURL:url];
}

- (void)openExistingRealm:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.canChooseFiles = YES;
    panel.allowedFileTypes = @[kRealmFileExtension];

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) { return; }
        NSURL *url = panel.URL;
        if (!url) { return; }
        [self openURL:url];
    }];
}

- (void)createTestRealm:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[kRealmFileExtension];
    panel.title = @"Generate";
    panel.prompt = @"Generate";
    panel.nameFieldStringValue = @"Test.realm";

    NSURL *defaultDir = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    if (defaultDir) {
        panel.directoryURL = defaultDir;
    }

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) { return; }
        NSURL *url = panel.URL;
        if (!url) { return; }

        NSFileManager *fileManager = [NSFileManager defaultManager];
        BOOL isDirectory = NO;
        if ([fileManager fileExistsAtPath:url.path isDirectory:&isDirectory] && !isDirectory) {
            [fileManager removeItemAtURL:url error:nil];
        }

        NSArray *classNames = @[[RealmTestClass0 className], [RealmTestClass1 className], [RealmTestClass2 className]];
        BOOL success = [RLMTestDataGenerator createRealmAtUrl:url withClassesNamed:classNames objectCount:1000];
        if (success) {
            [self openURL:url];
        }
    }];
}

- (void)openURL:(NSURL *)url
{
    [self close];
    [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:url
                                                                           display:YES
                                                                 completionHandler:^(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error) {
        if (error) {
            [NSApp presentError:error];
        }
    }];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
