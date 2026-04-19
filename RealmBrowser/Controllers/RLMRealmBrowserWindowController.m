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

@import Realm;
@import Realm.Private;
@import Realm.Dynamic;

#import "RLMRealmBrowserWindowController.h"
#import "RLMNavigationStack.h"
#import "RLMModelExporter.h"
#import "RLMExportIndicatorWindowController.h"
#import "RLMEncryptionKeyWindowController.h"
#import "RLMInspectorViewController.h"
#import "RLMBrowserConstants.h"

static NSToolbarItemIdentifier const kNavigationItemIdentifier = @"Navigation";
static NSToolbarItemIdentifier const kSearchItemIdentifier = @"Search";
static NSToolbarItemIdentifier const kInspectorToggleItemIdentifier = @"InspectorToggle";

NSString * const kRealmKeyWindowFrameForRealm = @"WindowFrameForRealm:%@";
NSString * const kRealmKeyOutlineWidthForRealm = @"OutlineWidthForRealm:%@";

@interface RLMRealmBrowserWindowController()<NSWindowDelegate>

@property (atomic, weak) NSSplitView *splitView;
@property (nonatomic, strong) NSSegmentedControl *navigationButtons;
@property (nonatomic, strong) NSSearchField *searchField;

@property (nonatomic, strong) RLMExportIndicatorWindowController *exportWindowController;
@property (nonatomic, strong) RLMEncryptionKeyWindowController *encryptionController;

@property (nonatomic, strong) RLMInspectorViewController *inspectorViewController;

@property (nonatomic, strong) RLMNotificationToken *documentNotificationToken;

@end

@implementation RLMRealmBrowserWindowController {
    RLMNavigationStack *navigationStack;
    BOOL _didPerformInitialSetup;
}

@dynamic document;

- (void)setDocument:(RLMDocument *)document {
    if (document == self.document) {
        return;
    }

    [self stopObservingDocument];

    [super setDocument:document];

    if (document && !_didPerformInitialSetup) {
        _didPerformInitialSetup = YES;
        [self performInitialWindowSetup];
    }

    if (self.windowLoaded && self.window.isVisible) {
        [self handleDocumentState];
    }
}

#pragma mark - NSWindowController Overrides

- (instancetype)init
{
    NSRect contentRect = NSMakeRect(0, 0, 1000, 700);
    NSWindowStyleMask mask = (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable |
                              NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect styleMask:mask backing:NSBackingStoreBuffered defer:NO];
    window.minSize = NSMakeSize(440, 200);
    window.releasedWhenClosed = NO;
    window.restorable = NO;
    window.titlebarAppearsTransparent = YES;
    window.toolbarStyle = NSWindowToolbarStyleUnified;
    window.collectionBehavior |= NSWindowCollectionBehaviorFullScreenPrimary;

    self = [super initWithWindow:window];
    if (self) {
        navigationStack = [[RLMNavigationStack alloc] init];

        // Build the pane view controllers and install the split view controller up-front,
        // before the window is shown. Restoring the window to its saved frame with a missing
        // contentViewController leaves an empty placeholder chrome, so we make sure the
        // real content is in place before any show path runs.
        self.outlineViewController = [[RLMTypeOutlineViewController alloc] init];
        self.outlineViewController.parentWindowController = self;
        self.tableViewController = [[RLMInstanceTableViewController alloc] init];
        self.tableViewController.parentWindowController = self;
        self.inspectorViewController = [[RLMInspectorViewController alloc] init];
        [self installSplitViewController];

        NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"RLMRealmBrowserToolbar"];
        toolbar.delegate = self;
        toolbar.allowsUserCustomization = YES;
        toolbar.autosavesConfiguration = YES;
        toolbar.displayMode = NSToolbarDisplayModeIconOnly;
        window.toolbar = toolbar;

        // Modify responder chain to handle shortcuts for table view (workaround for https://github.com/realm/realm-browser-osx/issues/241)
        self.outlineViewController.tableView.enclosingScrollView.nextResponder = self.tableViewController.tableView;
    }
    return self;
}

- (NSString *)windowNibName
{
    return nil;
}

// NSWindowController.windowDidLoad doesn't fire when the window is supplied via initWithWindow:.
// This runs from -setDocument: the first time the document is assigned so we can pick up
// document-specific configuration (autosave keys etc.) that aren't available in -init.
- (void)performInitialWindowSetup
{
    NSString *realmPath = self.document.fileURL.path;
    NSString *windowAutosave = [NSString stringWithFormat:kRealmKeyWindowFrameForRealm, realmPath];
    if (![self.window setFrameUsingName:windowAutosave]) {
        [self.window center];
    }
    [self setWindowFrameAutosaveName:windowAutosave];

    self.splitView.autosaveName = [NSString stringWithFormat:kRealmKeyOutlineWidthForRealm, realmPath];
}

- (void)installSplitViewController
{
    NSSplitViewController *splitVC = [[NSSplitViewController alloc] init];

    NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:self.outlineViewController];
    sidebarItem.minimumThickness = 225;
    sidebarItem.maximumThickness = 400;
    sidebarItem.canCollapse = NO;
    [splitVC addSplitViewItem:sidebarItem];

    NSSplitViewItem *contentItem = [NSSplitViewItem splitViewItemWithViewController:self.tableViewController];
    contentItem.minimumThickness = 400;
    [splitVC addSplitViewItem:contentItem];

    NSSplitViewItem *inspectorItem = [NSSplitViewItem inspectorWithViewController:self.inspectorViewController];
    inspectorItem.minimumThickness = 260;
    inspectorItem.maximumThickness = 420;
    inspectorItem.canCollapse = YES;
    [splitVC addSplitViewItem:inspectorItem];

    self.window.contentViewController = splitVC;
    self.splitView = splitVC.splitView;
}

- (NSToolbarItem *)makeNavigationToolbarItem
{
    NSSegmentedControl *segmented = [NSSegmentedControl segmentedControlWithImages:@[
        [NSImage imageWithSystemSymbolName:@"chevron.backward" accessibilityDescription:@"Back"],
        [NSImage imageWithSystemSymbolName:@"chevron.forward" accessibilityDescription:@"Forward"],
    ] trackingMode:NSSegmentSwitchTrackingMomentary target:self action:@selector(userClicksOnNavigationButtons:)];
    segmented.segmentStyle = NSSegmentStyleSeparated;

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:kNavigationItemIdentifier];
    item.view = segmented;
    item.label = @"Navigation";
    item.paletteLabel = @"Navigation";
    item.navigational = YES;

    self.navigationButtons = segmented;
    return item;
}

- (NSToolbarItem *)makeSearchToolbarItem
{
    NSSearchField *search = [[NSSearchField alloc] init];
    search.target = self;
    search.action = @selector(searchAction:);
    search.translatesAutoresizingMaskIntoConstraints = NO;
    [search.widthAnchor constraintEqualToConstant:200].active = YES;

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:kSearchItemIdentifier];
    item.view = search;
    item.label = @"Search";
    item.paletteLabel = @"Search";

    self.searchField = search;
    return item;
}

- (NSToolbarItem *)makeInspectorToggleItem
{
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:kInspectorToggleItemIdentifier];
    item.label = @"Inspector";
    item.paletteLabel = @"Show/Hide Inspector";
    item.toolTip = @"Show or hide the inspector";
    item.image = [NSImage imageWithSystemSymbolName:@"sidebar.right" accessibilityDescription:@"Inspector"];
    item.target = nil;
    item.action = @selector(toggleInspector:);
    return item;
}

#pragma mark - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return @[kNavigationItemIdentifier,
             kSearchItemIdentifier,
             kInspectorToggleItemIdentifier,
             NSToolbarFlexibleSpaceItemIdentifier,
             NSToolbarSidebarTrackingSeparatorItemIdentifier];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return @[NSToolbarSidebarTrackingSeparatorItemIdentifier,
             kNavigationItemIdentifier,
             NSToolbarFlexibleSpaceItemIdentifier,
             kSearchItemIdentifier,
             kInspectorToggleItemIdentifier];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
    if ([itemIdentifier isEqualToString:kNavigationItemIdentifier]) {
        return [self makeNavigationToolbarItem];
    }
    if ([itemIdentifier isEqualToString:kSearchItemIdentifier]) {
        return [self makeSearchToolbarItem];
    }
    if ([itemIdentifier isEqualToString:kInspectorToggleItemIdentifier]) {
        return [self makeInspectorToggleItem];
    }
    if ([itemIdentifier isEqualToString:NSToolbarSidebarTrackingSeparatorItemIdentifier]) {
        return [NSTrackingSeparatorToolbarItem trackingSeparatorToolbarItemWithIdentifier:itemIdentifier splitView:self.splitView dividerIndex:0];
    }
    return nil;
}

- (IBAction)showWindow:(id)sender
{
    [super showWindow:sender];
    [self handleDocumentState];
}

#pragma mark - Document observation

- (void)handleDocumentState {
    switch (self.document.state) {
        case RLMDocumentStateRequiresFormatUpgrade:
            [self handleFormatUpgrade];
            break;

        case RLMDocumentStateNeedsEncryptionKey:
            [self handleEncryption];
            break;

        case RLMDocumentStateLoaded:
            [self realmDidLoad];
            break;

        case RLMDocumentStateUnrecoverableError:
            [self handleUnrecoverableError];
            break;
    }
}

- (void)startObservingDocument {
    __weak typeof(self) weakSelf = self;

    [self.documentNotificationToken invalidate];

    self.documentNotificationToken = [self.document.presentedRealm.realm addNotificationBlock:^(RLMNotification notification, RLMRealm *realm) {
        // Send notifications to all document's window controllers
        [weakSelf.document.windowControllers makeObjectsPerformSelector:@selector(handleDocumentChange)];
    }];
}

- (void)handleDocumentChange {
    [self reloadAfterEdit];
}

- (void)stopObservingDocument {
    [self.documentNotificationToken invalidate];
}

- (void)realmDidLoad {
    [self.outlineViewController realmDidLoad];
    [self.tableViewController realmDidLoad];
    
    [self updateNavigationButtons];

    id firstItem = self.document.presentedRealm.topLevelClasses.firstObject;
    if (firstItem != nil && navigationStack.currentState == nil) {
        RLMNavigationState *initState = [[RLMNavigationState alloc] initWithSelectedType:firstItem index:NSNotFound];
        [self addNavigationState:initState fromViewController:nil];
    }

    [self startObservingDocument];
}

- (void)handleFormatUpgrade {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"\"%@\" is at an older file format version and must be upgraded before it can be opened. Would you like to proceed?", self.document.fileURL.lastPathComponent];
    alert.informativeText = @"If the file is upgraded, it will no longer be compatible with older versions of Realm. File format upgrades are permanent and cannot be undone.";

    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Proceed with Upgrade"];

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertSecondButtonReturn) {
            [self.document loadByPerformingFormatUpgradeWithError:nil];

            dispatch_async(dispatch_get_main_queue(), ^{
                [self handleDocumentState];
            });
        } else {
            [self.document close];
        }
    }];
}

- (void)handleEncryption {
    self.encryptionController = [[RLMEncryptionKeyWindowController alloc] init];

    [self.encryptionController showSheetForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSModalResponseOK) {
            [self.document loadWithEncryptionKey:self.encryptionController.encryptionKey error:nil];

            dispatch_async(dispatch_get_main_queue(), ^{
                [self handleDocumentState];
            });
        } else {
            [self.document close];
        }

        self.encryptionController = nil;
    }];
}

- (void)handleUnrecoverableError {
    NSAlert *alert;

    if (self.document.error != nil) {
        alert = [NSAlert alertWithError:self.document.error];
    } else {
        alert = [[NSAlert alloc] init];

        alert.messageText = @"Realm couldn't be opened";
        alert.alertStyle = NSAlertStyleCritical;
    }

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        [self.document close];
    }];
}

#pragma mark - Public methods - Accessors

- (RLMNavigationState *)currentState
{
    return navigationStack.currentState;
}

#pragma mark - Public methods - Menu items

- (void)saveModelsForLanguage:(RLMModelExporterLanguage)language
{
    NSArray *objectSchemas = self.document.presentedRealm.realm.schema.objectSchema;
    [RLMModelExporter saveModelsForSchemas:objectSchemas inLanguage:language window:self.window];
}

- (IBAction)saveJavaModels:(id)sender
{
    [self saveModelsForLanguage:RLMModelExporterLanguageJava];
}

- (IBAction)saveObjcModels:(id)sender
{
    [self saveModelsForLanguage:RLMModelExporterLanguageObjectiveC];
}

- (IBAction)saveSwiftModels:(id)sender
{
    [self saveModelsForLanguage:RLMModelExporterLanguageSwift];
}

- (IBAction)saveJavaScriptModels:(id)sender
{
    [self saveModelsForLanguage:RLMModelExporterLanguageJavaScript];
}

- (IBAction)saveCSharpModels:(id)sender
{
    [self saveModelsForLanguage:RLMModelExporterLanguageCSharp];
}

- (IBAction)exportToCompactedRealm:(id)sender
{
    NSString *fileName = self.document.fileURL.lastPathComponent ?: @"Compacted";

    if (![fileName.pathExtension isEqualToString:kRealmFileExtension]) {
        fileName = [fileName.stringByDeletingPathExtension stringByAppendingPathExtension:kRealmFileExtension];
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.canCreateDirectories = YES;
    panel.nameFieldStringValue = fileName;
    panel.prompt = @"Export";

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result){
        if (result != NSModalResponseOK) {
            return;
        }

        [panel orderOut:nil];

        [self exportAndCompactCopyOfRealmFileAtURL:panel.URL];
    }];
}

- (void)exportAndCompactCopyOfRealmFileAtURL:(NSURL *)realmFileURL
{
    //Check that this won't end up overwriting the original file
    if ([realmFileURL.path.lowercaseString isEqualToString:self.document.fileURL.path.lowercaseString]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"You cannot overwrite the original Realm file.";
        alert.informativeText = @"Please choose a different location in which to save this Realm file.";
        [alert runModal];
        return;
    }
    
    //Ensure a file with the same name doesn't already exist
    BOOL directory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:realmFileURL.path isDirectory:&directory] && !directory) {
        NSError *error = nil;
        if (![[NSFileManager defaultManager] removeItemAtURL:realmFileURL error:&error]) {
            [NSApp presentError:error];
            return;
        }
    }

    void (^closeExportWindowOnMainThreadAndShowError)(NSError *) = ^void(NSError *error) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self.window endSheet:self.exportWindowController.window];

            if (error != nil) {
                [NSApp presentError:error];
            } else {
                [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[realmFileURL]];
            }
        });
    };

    //Display an 'exporting' progress indicator
    self.exportWindowController = [[RLMExportIndicatorWindowController alloc] init];
    [self.window beginSheet:self.exportWindowController.window completionHandler:nil];
    
    //Perform the export/compact operations on a background thread as they can potentially be time-consuming
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSError *error = nil;

        RLMRealm *currentThreadRealm = [RLMRealm realmWithConfiguration:self.document.presentedRealm.realm.configuration error:&error];
        if (currentThreadRealm == nil) {
            closeExportWindowOnMainThreadAndShowError(error);
            return;
        }

        if (![currentThreadRealm writeCopyToURL:realmFileURL encryptionKey:nil error:&error]) {
            closeExportWindowOnMainThreadAndShowError(error);
            return;
        }

        closeExportWindowOnMainThreadAndShowError(nil);
    });
}

#pragma mark - Public methods - User Actions

- (void)reloadAllWindows
{
    NSArray *windowControllers = [self.document windowControllers];
    
    for (RLMRealmBrowserWindowController *wc in windowControllers) {
        [wc reloadAfterEdit];
    }
}

- (void)inspectObject:(id)object
{
    [self.inspectorViewController setInspectedObject:[object isKindOfClass:[RLMObject class]] ? object : nil];
}

- (void)reloadAfterEdit
{
    [self.outlineViewController reloadData];

    if (self.tableViewController.displayedType.isInvalidated) {
        [navigationStack reset];
        [self realmDidLoad];
    } else {
        [self.tableViewController reloadData];
    }
}

#pragma mark - Public methods - Navigation

- (void)addNavigationState:(RLMNavigationState *)state fromViewController:(RLMViewController *)controller
{
    if (!controller.navigationFromHistory) {
        RLMNavigationState *oldState = navigationStack.currentState;

        [navigationStack pushState:state];
        [self updateNavigationButtons];

        if (controller == self.tableViewController || controller == nil) {
            [self.outlineViewController updateUsingState:state oldState:oldState];
        }

        [self.tableViewController updateUsingState:state oldState:oldState];
    }

    [self updateWindowSubtitle];

    // Searching is not implemented for link arrays yet
    BOOL isArray = [state isMemberOfClass:[RLMArrayNavigationState class]];
    [self.searchField setEnabled:!isArray];
}

- (void)updateWindowSubtitle
{
    self.window.subtitle = navigationStack.currentState.selectedType.name ?: @"";
}

- (void)newWindowWithNavigationState:(RLMNavigationState *)state
{
    RLMRealmBrowserWindowController *wc = [[RLMRealmBrowserWindowController alloc] init];

    [self.document addWindowController:wc];
    [self.document showWindows];

    [wc addNavigationState:state fromViewController:wc.tableViewController];
}

- (IBAction)userClicksOnNavigationButtons:(NSSegmentedControl *)buttons
{
    RLMNavigationState *oldState = navigationStack.currentState;
    
    switch (buttons.selectedSegment) {
        case 0: { // Navigate backwards
            RLMNavigationState *state = [navigationStack navigateBackward];
            if (state != nil) {
                [self.outlineViewController updateUsingState:state oldState:oldState];
                [self.tableViewController updateUsingState:state oldState:oldState];
            }
            break;
        }
        case 1: { // Navigate forwards
            RLMNavigationState *state = [navigationStack navigateForward];
            if (state != nil) {
                [self.outlineViewController updateUsingState:state oldState:oldState];
                [self.tableViewController updateUsingState:state oldState:oldState];
            }
            break;
        }
        default:
            break;
    }

    [self updateNavigationButtons];
    [self updateWindowSubtitle];
}

- (IBAction)searchAction:(NSSearchFieldCell *)searchCell
{
    NSString *searchText = searchCell.stringValue;
    RLMTypeNode *typeNode = navigationStack.currentState.selectedType;

    // Return to parent class (showing all objects) when the user clears the search text
    if (searchText.length == 0) {
        if ([navigationStack.currentState isMemberOfClass:[RLMQueryNavigationState class]]) {
            RLMNavigationState *state = [[RLMNavigationState alloc] initWithSelectedType:typeNode index:0];
            [self addNavigationState:state fromViewController:self.tableViewController];
        }
        return;
    }

    NSArray *columns = typeNode.propertyColumns;
    NSUInteger columnCount = columns.count;
    RLMRealm *realm = self.document.presentedRealm.realm;

    NSMutableArray *predicates = [NSMutableArray array];

    NSNumberFormatter *floatFormatter = [[NSNumberFormatter alloc] init];
    NSNumberFormatter *integerFormatter = [[NSNumberFormatter alloc] init];
    integerFormatter.allowsFloats = NO;

    for (NSUInteger index = 0; index < columnCount; index++) {

        RLMClassProperty *property = columns[index];
        NSExpression *propertyExpression = [NSExpression expressionForKeyPath:property.name];
        NSExpression *valueExpression;
        NSPredicateOperatorType comparisonOperator = NSEqualToPredicateOperatorType;
        NSComparisonPredicateOptions comparisonOptions = 0;

        switch (property.type) {
            case RLMPropertyTypeBool: {
                if ([searchText caseInsensitiveCompare:@"true"] == NSOrderedSame ||
                    [searchText caseInsensitiveCompare:@"YES"] == NSOrderedSame) {
                    valueExpression = [NSExpression expressionForConstantValue:@YES];
                }
                else if ([searchText caseInsensitiveCompare:@"false"] == NSOrderedSame ||
                         [searchText caseInsensitiveCompare:@"NO"] == NSOrderedSame) {
                    valueExpression = [NSExpression expressionForConstantValue:@NO];
                }
                break;
            }
            case RLMPropertyTypeInt: {
                NSNumber *value = [integerFormatter numberFromString:searchText];
                if (value) {
                    valueExpression = [NSExpression expressionForConstantValue:value];
                }
                break;
            }
            case RLMPropertyTypeString: {
                valueExpression = [NSExpression expressionForConstantValue:searchText];
                comparisonOperator = NSContainsPredicateOperatorType;
                comparisonOptions = NSCaseInsensitivePredicateOption;

                break;
            }
            case RLMPropertyTypeFloat:
            case RLMPropertyTypeDouble: {
                NSNumber *value = [floatFormatter numberFromString:searchText];
                if (value) {
                    valueExpression = [NSExpression expressionForConstantValue:value];
                }
                break;
            }
            default:
                break;
        }

        if (!valueExpression) {
            // We were unable to convert the search text into a predicate for this property type.
            continue;
        }

        NSPredicate *predicate = [NSComparisonPredicate predicateWithLeftExpression:propertyExpression
                                                                    rightExpression:valueExpression
                                                                           modifier:NSDirectPredicateModifier
                                                                               type:comparisonOperator
                                                                            options:comparisonOptions];
        [predicates addObject:predicate];
    }

    NSPredicate *predicate = [NSCompoundPredicate orPredicateWithSubpredicates:predicates];
    RLMResults *result = [realm objects:typeNode.name withPredicate:predicate];

    RLMQueryNavigationState *state = [[RLMQueryNavigationState alloc] initWithQuery:searchText type:typeNode results:result];
    [self addNavigationState:state fromViewController:self.tableViewController];
}

#pragma mark - Private methods

- (void)updateNavigationButtons
{
    [self.navigationButtons setEnabled:[navigationStack canNavigateBackward] forSegment:0];
    [self.navigationButtons setEnabled:[navigationStack canNavigateForward] forSegment:1];
}

@end
