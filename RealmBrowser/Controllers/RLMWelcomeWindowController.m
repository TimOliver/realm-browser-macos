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
#import "RLMWelcomeActionButton.h"
#import "RLMWelcomeRecentsCellView.h"
#import "TestClasses.h"

// NSImageView swallows mouse-down events by default, which blocks the window's
// movableByWindowBackground drag. This subclass opts the view into the drag.
@interface RLMWelcomeDraggableImageView : NSImageView
@end
@implementation RLMWelcomeDraggableImageView
- (BOOL)mouseDownCanMoveWindow { return YES; }
@end

static const CGFloat kWelcomeWindowWidth = 750.0;
static const CGFloat kWelcomeWindowHeight = 420.0;
static const CGFloat kRightPaneWidth = 280.0;
static const CGFloat kAppIconSize = 130.0;
static const CGFloat kActionButtonWidth = 350.0;
static const CGFloat kActionButtonHeight = 34.0;
static const CGFloat kRecentsRowHeight = 44.0;

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
    window.opaque = NO;
    window.backgroundColor = [NSColor clearColor];
    if (@available(macOS 11.0, *)) {
        window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    }
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

    // Within-window blending means the materials render from their own palette
    // instead of sampling the desktop, so the panes don't shift when the window
    // loses key/main status.
    NSVisualEffectView *leftPane = [[NSVisualEffectView alloc] init];
    leftPane.translatesAutoresizingMaskIntoConstraints = NO;
    leftPane.material = NSVisualEffectMaterialHeaderView;
    leftPane.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    leftPane.state = NSVisualEffectStateActive;
    leftPane.emphasized = YES;
    [contentView addSubview:leftPane];

    NSVisualEffectView *rightPane = [[NSVisualEffectView alloc] init];
    rightPane.translatesAutoresizingMaskIntoConstraints = NO;
    rightPane.material = NSVisualEffectMaterialUnderWindowBackground;
    rightPane.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    rightPane.state = NSVisualEffectStateActive;
    rightPane.emphasized = YES;
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
    RLMWelcomeDraggableImageView *iconView = [[RLMWelcomeDraggableImageView alloc] init];
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

    RLMWelcomeActionButton *openButton = [[RLMWelcomeActionButton alloc] initWithTitle:@"Open Existing Realm\u2026"
                                                                            symbolName:@"folder"];
    openButton.target = self;
    openButton.action = @selector(openExistingRealm:);
    [leftPane addSubview:openButton];

    RLMWelcomeActionButton *createButton = [[RLMWelcomeActionButton alloc] initWithTitle:@"Create Test Realm\u2026"
                                                                              symbolName:@"doc.badge.plus"];
    createButton.target = self;
    createButton.action = @selector(createTestRealm:);
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
        [openButton.topAnchor constraintEqualToAnchor:versionLabel.bottomAnchor constant:38.0],
        [openButton.widthAnchor constraintEqualToConstant:kActionButtonWidth],
        [openButton.heightAnchor constraintEqualToConstant:kActionButtonHeight],

        [createButton.centerXAnchor constraintEqualToAnchor:leftPane.centerXAnchor],
        [createButton.topAnchor constraintEqualToAnchor:openButton.bottomAnchor constant:10.0],
        [createButton.widthAnchor constraintEqualToConstant:kActionButtonWidth],
        [createButton.heightAnchor constraintEqualToConstant:kActionButtonHeight],
    ]];
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
    if (@available(macOS 11.0, *)) {
        tableView.style = NSTableViewStyleSourceList;
    }
    tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleSourceList;
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
        [scrollView.topAnchor constraintEqualToAnchor:rightPane.topAnchor constant:0.0],
        [scrollView.bottomAnchor constraintEqualToAnchor:rightPane.bottomAnchor constant:0.0],
        [scrollView.leadingAnchor constraintEqualToAnchor:rightPane.leadingAnchor constant:0.0],
        [scrollView.trailingAnchor constraintEqualToAnchor:rightPane.trailingAnchor constant:0.0],

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
