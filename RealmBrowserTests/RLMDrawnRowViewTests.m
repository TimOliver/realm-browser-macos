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

@import XCTest;
@import Cocoa;
@import Realm;

#import "RLMCellContent.h"
#import "RLMDrawnRowView.h"
#import "RLMTableView.h"
#import "RLMInstanceTableViewController.h"
#import "RLMRealmNode.h"
#import "RLMClassNode.h"
#import "RLMTableColumn.h"
#import "RLMClassProperty.h"
#import "RLMTestDataGenerator.h"
#import "TestClasses.h"

// beginInlineEditingAtRow:column: and the editor field are private to the controller;
// the test drives them directly to check the editor's geometry and bookkeeping.
@interface RLMInstanceTableViewController (RLMDrawnRowViewTests)
@property (nonatomic, strong) NSTextField *inlineEditorField;
@property (nonatomic) BOOL inlineEditingActive;
- (void)beginInlineEditingAtRow:(NSInteger)row column:(NSInteger)column;
- (void)discardInlineEditing;
@end

// A data source/delegate that serves the same RLMCellContent per column to every row.
@interface RLMDrawnRowViewTestHost : NSObject <NSTableViewDataSource, NSTableViewDelegate, RLMDrawnRowViewDataSource>
@property (nonatomic, copy) NSArray<RLMCellContent *> *contentsByColumn;
@property (nonatomic) NSInteger rowCount;
@end

@implementation RLMDrawnRowViewTestHost
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.rowCount; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row { return nil; }
- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row
{
    RLMDrawnRowView *rowView = [tableView makeViewWithIdentifier:RLMDrawnRowViewReuseIdentifier owner:nil];
    if (rowView == nil) {
        rowView = [[RLMDrawnRowView alloc] initWithFrame:NSZeroRect];
        rowView.identifier = RLMDrawnRowViewReuseIdentifier;
    }
    rowView.tableView = tableView;
    rowView.contentDataSource = self;
    return rowView;
}
- (RLMCellContent *)rowView:(RLMDrawnRowView *)rowView contentForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSUInteger index = [rowView.tableView.tableColumns indexOfObject:tableColumn];
    return index < self.contentsByColumn.count ? self.contentsByColumn[index] : nil;
}
@end

// YES if the pixels of `view` inside the horizontal span of `rect` are not a single colour.
static BOOL RLMViewHasInkInColumnSpan(NSView *view, NSRect rect)
{
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    CGFloat scale = rep.pixelsWide / NSWidth(view.bounds);
    NSInteger minX = (NSInteger)floor(NSMinX(rect) * scale), maxX = (NSInteger)ceil(NSMaxX(rect) * scale);
    NSColor *first = nil;
    for (NSInteger y = 0; y < rep.pixelsHigh; y++) {
        for (NSInteger x = MAX(minX, 0); x < MIN(maxX, rep.pixelsWide); x++) {
            NSColor *color = [rep colorAtX:x y:y];
            if (first == nil) { first = color; continue; }
            if (![color isEqual:first]) { return YES; }
        }
    }
    return NO;
}

@interface RLMDrawnRowViewTests : XCTestCase
@property (nonatomic, strong) NSWindow *window;          // keeps the offscreen view hierarchy alive
@property (nonatomic, strong) RLMDrawnRowViewTestHost *host;
@end

@implementation RLMDrawnRowViewTests
#pragma mark - RLMCellContent

- (void)testTextContentKeepsTextAndPlaceholderFlag
{
    RLMCellContent *content = [RLMCellContent textContent:@"hello" showsNilPlaceholder:YES];
    XCTAssertEqual(content.kind, RLMCellContentKindText);
    XCTAssertEqualObjects(content.text, @"hello");
    XCTAssertTrue(content.showsNilPlaceholder);
    XCTAssertNil(content.badgeText);
    XCTAssertEqualObjects(content.accessibilityValueString, @"hello");
}

- (void)testTextContentNeverHasNilText
{
    RLMCellContent *content = [RLMCellContent textContent:nil showsNilPlaceholder:YES];
    XCTAssertEqualObjects(content.text, @"");
    XCTAssertEqualObjects(content.accessibilityValueString, @"nil");
    XCTAssertEqualObjects([RLMCellContent textContent:nil showsNilPlaceholder:NO].accessibilityValueString, @"");
}

- (void)testLinkBoolAndBadgeContent
{
    RLMCellContent *link = [RLMCellContent linkContent:@"Person(...)"];
    XCTAssertEqual(link.kind, RLMCellContentKindLink);
    XCTAssertEqualObjects(link.text, @"Person(...)");
    XCTAssertTrue(link.showsNilPlaceholder, @"object links are optional: an empty link draws the nil placeholder");
    XCTAssertEqualObjects([RLMCellContent linkContent:@""].accessibilityValueString, @"nil");

    RLMCellContent *yes = [RLMCellContent boolContent:YES];
    XCTAssertEqual(yes.kind, RLMCellContentKindBool);
    XCTAssertTrue(yes.boolValue);
    XCTAssertEqualObjects(yes.accessibilityValueString, @"true");
    XCTAssertEqualObjects([RLMCellContent boolContent:NO].accessibilityValueString, @"false");

    RLMCellContent *badge = [RLMCellContent badgeContent:@"Dog" count:3];
    XCTAssertEqual(badge.kind, RLMCellContentKindBadge);
    XCTAssertEqualObjects(badge.text, @"Dog");
    XCTAssertEqualObjects(badge.badgeText, @"3");
    XCTAssertEqualObjects(badge.accessibilityValueString, @"Dog, 3 items");
    XCTAssertEqualObjects([RLMCellContent badgeContent:@"Dog" count:1].accessibilityValueString, @"Dog, 1 item");
}

#pragma mark - Fixture

- (NSTableView *)makeTableViewWithColumnCount:(NSUInteger)columnCount columnWidth:(CGFloat)columnWidth
{
    self.host = [[RLMDrawnRowViewTestHost alloc] init];
    self.host.rowCount = 3;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 200)
                                              styleMask:NSWindowStyleMaskBorderless
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:self.window.contentView.bounds];
    NSTableView *tableView = [[RLMTableView alloc] initWithFrame:scrollView.bounds];
    tableView.rowHeight = 18.0;
    tableView.headerView = nil;
    for (NSUInteger i = 0; i < columnCount; i++) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"column%lu", (unsigned long)i]];
        column.width = columnWidth;
        [tableView addTableColumn:column];
    }
    tableView.dataSource = self.host;
    tableView.delegate = self.host;
    scrollView.documentView = tableView;
    [self.window.contentView addSubview:scrollView];
    [tableView reloadData];
    [tableView layoutSubtreeIfNeeded];
    return tableView;
}

- (NSRect)cellRectOfRowView:(NSTableRowView *)rowView tableView:(NSTableView *)tableView column:(NSInteger)column row:(NSInteger)row
{
    return [rowView convertRect:[tableView frameOfCellAtColumn:column row:row] fromView:tableView];
}

#pragma mark - Drawing

- (void)testRowViewIsReusedFromThePoolAndKnowsItsRow
{
    NSTableView *tableView = [self makeTableViewWithColumnCount:2 columnWidth:100.0];
    RLMDrawnRowView *rowView = (RLMDrawnRowView *)[tableView rowViewAtRow:1 makeIfNecessary:YES];
    XCTAssertTrue([rowView isKindOfClass:[RLMDrawnRowView class]]);
    XCTAssertEqualObjects(rowView.identifier, RLMDrawnRowViewReuseIdentifier);
    XCTAssertEqual([tableView rowForView:rowView], 1);
    XCTAssertEqual(rowView.tableView, tableView);
}

- (void)testRowViewDrawsTextOnlyInColumnsThatHaveContent
{
    NSTableView *tableView = [self makeTableViewWithColumnCount:3 columnWidth:120.0];
    self.host.contentsByColumn = @[[RLMCellContent textContent:@"Hello world" showsNilPlaceholder:NO],
                                   [RLMCellContent textContent:@"" showsNilPlaceholder:NO],
                                   [RLMCellContent textContent:@"" showsNilPlaceholder:YES]];
    NSTableRowView *rowView = [tableView rowViewAtRow:0 makeIfNecessary:YES];

    XCTAssertTrue(RLMViewHasInkInColumnSpan(rowView, [self cellRectOfRowView:rowView tableView:tableView column:0 row:0]), @"text column draws");
    XCTAssertFalse(RLMViewHasInkInColumnSpan(rowView, [self cellRectOfRowView:rowView tableView:tableView column:1 row:0]), @"empty, non-optional column draws nothing");
    XCTAssertTrue(RLMViewHasInkInColumnSpan(rowView, [self cellRectOfRowView:rowView tableView:tableView column:2 row:0]), @"optional empty column draws the nil placeholder");
}

- (void)testRowViewDrawsLinkBoolAndBadgeKinds
{
    NSTableView *tableView = [self makeTableViewWithColumnCount:3 columnWidth:120.0];
    self.host.contentsByColumn = @[[RLMCellContent linkContent:@"Person(...)"],
                                   [RLMCellContent boolContent:YES],
                                   [RLMCellContent badgeContent:@"Dog" count:12]];
    NSTableRowView *rowView = [tableView rowViewAtRow:0 makeIfNecessary:YES];
    for (NSInteger column = 0; column < 3; column++) {
        XCTAssertTrue(RLMViewHasInkInColumnSpan(rowView, [self cellRectOfRowView:rowView tableView:tableView column:column row:0]),
                      @"column %ld should draw", (long)column);
    }
}

- (void)testRowViewDrawsNothingWhenDetachedFromTable
{
    RLMDrawnRowView *rowView = [[RLMDrawnRowView alloc] initWithFrame:NSMakeRect(0, 0, 200, 18)];
    XCTAssertFalse(RLMViewHasInkInColumnSpan(rowView, rowView.bounds));
}

- (void)testSharedTextStyle
{
    XCTAssertEqualObjects([RLMDrawnRowView cellTextFont], [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightRegular]);
    XCTAssertGreaterThan([RLMDrawnRowView cellTextHeight], 10.0);
    XCTAssertEqualObjects(RLMDrawnRowViewReuseIdentifier, @"RLMDrawnRowView");
}

#pragma mark - Controller content mapping

- (RLMTableColumn *)columnForProperty:(RLMClassProperty *)classProperty
{
    RLMTableColumn *column = [[RLMTableColumn alloc] initWithIdentifier:classProperty.name];
    column.propertyType = classProperty.type;
    column.classProperty = classProperty;
    return column;
}

- (void)testControllerMapsPropertyTypesToCellContent
{
    NSString *fileName = [NSString stringWithFormat:@"%@.realm", [[NSUUID UUID] UUIDString]];
    NSURL *fileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
    @autoreleasepool {
        // The generator opens the file non-dynamically; the cached RLMRealm has to go
        // away before RLMRealmNode can reopen it in dynamic mode.
        XCTAssertTrue([RLMTestDataGenerator createRealmAtUrl:fileURL withClassesNamed:@[[RealmTestClass1 className]] objectCount:3 encryptionKey:nil]);
    }

    RLMRealmNode *realmNode = [[RLMRealmNode alloc] initWithFileURL:fileURL];
    NSError *error = nil;
    XCTAssertTrue([realmNode connect:&error]);
    XCTAssertNil(error);

    RLMClassNode *classNode = nil;
    for (RLMClassNode *node in realmNode.topLevelClasses) {
        if ([node.name isEqualToString:[RealmTestClass1 className]]) { classNode = node; }
    }
    XCTAssertNotNil(classNode);

    RLMInstanceTableViewController *controller = [[RLMInstanceTableViewController alloc] init];
    (void)controller.view; // loads the nib; awakeFromNib creates the formatters
    controller.displayedType = classNode;

    RLMObject *object = [classNode instanceAtIndex:0];
    NSMutableDictionary<NSString *, RLMCellContent *> *contents = [NSMutableDictionary dictionary];
    for (RLMClassProperty *classProperty in classNode.propertyColumns) {
        contents[classProperty.name] = [controller rowView:nil contentForTableColumn:[self columnForProperty:classProperty] row:0];
    }

    XCTAssertEqual(contents[@"integerValue"].kind, RLMCellContentKindText);
    XCTAssertEqualObjects(contents[@"integerValue"].text, [controller displayedStringForColumn:classNode.propertyColumns[0] row:0]);
    XCTAssertGreaterThan(contents[@"integerValue"].text.length, 0u);
    XCTAssertFalse(contents[@"integerValue"].showsNilPlaceholder, @"non-optional properties draw nothing for empty text");

    XCTAssertEqual(contents[@"boolValue"].kind, RLMCellContentKindBool);
    XCTAssertEqual(contents[@"boolValue"].boolValue, [object[@"boolValue"] boolValue]);

    XCTAssertEqual(contents[@"floatValue"].kind, RLMCellContentKindText);
    XCTAssertEqual(contents[@"doubleValue"].kind, RLMCellContentKindText);
    XCTAssertEqual(contents[@"stringValue"].kind, RLMCellContentKindText);
    XCTAssertEqual(contents[@"dateValue"].kind, RLMCellContentKindText);
    XCTAssertGreaterThan(contents[@"dateValue"].text.length, 0u);

    RLMArray *array = object[@"arrayReference"];
    XCTAssertEqual(contents[@"arrayReference"].kind, RLMCellContentKindBadge);
    XCTAssertEqualObjects(contents[@"arrayReference"].badgeText, [@(array.count) stringValue]);
    XCTAssertEqualObjects(contents[@"arrayReference"].text, [RealmTestClass0 className]);

    // The array gutter column has no backing property and shows the row index.
    RLMTableColumn *gutter = [[RLMTableColumn alloc] initWithIdentifier:@"#"];
    XCTAssertEqualObjects([controller rowView:nil contentForTableColumn:gutter row:7].text, @"7");

    // A plain NSTableColumn (no RLMTableColumn) yields nothing.
    XCTAssertNil([controller rowView:nil contentForTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"x"] row:0]);
}

#pragma mark - Redraw helpers

- (void)testRedrawHelpersMarkOnlyTheRequestedRowViews
{
    RLMTableView *tableView = (RLMTableView *)[self makeTableViewWithColumnCount:1 columnWidth:100.0];
    [tableView rowViewAtRow:0 makeIfNecessary:YES];
    [tableView rowViewAtRow:1 makeIfNecessary:YES];
    [tableView rowViewAtRow:2 makeIfNecessary:YES];
    // AppKit only clears needsDisplay through an actual display pass (assigning NO is
    // ignored), so draw the fresh row views once to get a clean baseline.
    [tableView enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *rowView, NSInteger row) {
        [rowView displayIfNeeded];
    }];

    [tableView redrawRowsAtIndexes:[NSIndexSet indexSetWithIndex:1]];
    XCTAssertFalse([tableView rowViewAtRow:0 makeIfNecessary:NO].needsDisplay);
    XCTAssertTrue([tableView rowViewAtRow:1 makeIfNecessary:NO].needsDisplay);
    XCTAssertFalse([tableView rowViewAtRow:2 makeIfNecessary:NO].needsDisplay);

    [tableView redrawAllRows];
    [tableView enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *rowView, NSInteger row) {
        XCTAssertTrue(rowView.needsDisplay, @"row %ld should be marked", (long)row);
    }];

    // Out-of-range indexes are ignored.
    [tableView redrawRowsAtIndexes:[NSIndexSet indexSetWithIndex:99]];
}

#pragma mark - Inline editing

// Builds a controller showing `classNode` inside an offscreen window, with row views made.
- (RLMInstanceTableViewController *)hostedControllerForClassNode:(RLMClassNode *)classNode
{
    RLMInstanceTableViewController *controller = [[RLMInstanceTableViewController alloc] init];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 400)
                                              styleMask:NSWindowStyleMaskBorderless
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    controller.view.frame = [self.window.contentView bounds];
    [self.window.contentView addSubview:controller.view];
    controller.displayedType = classNode;
    [controller.realmTableView setupColumnsWithType:classNode];
    [controller.realmTableView reloadData];
    [controller.view layoutSubtreeIfNeeded];
    [controller.realmTableView tile];
    return controller;
}

- (void)testInlineEditorCoversOnlyTheEditedCellOfTheRowView
{
    NSString *fileName = [NSString stringWithFormat:@"%@.realm", [[NSUUID UUID] UUIDString]];
    NSURL *fileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
    @autoreleasepool {
        XCTAssertTrue([RLMTestDataGenerator createRealmAtUrl:fileURL withClassesNamed:@[[RealmTestClass1 className]] objectCount:5 encryptionKey:nil]);
    }
    RLMRealmNode *realmNode = [[RLMRealmNode alloc] initWithFileURL:fileURL];
    XCTAssertTrue([realmNode connect:nil]);
    RLMClassNode *classNode = nil;
    for (RLMClassNode *node in realmNode.topLevelClasses) {
        if ([node.name isEqualToString:[RealmTestClass1 className]]) { classNode = node; }
    }
    XCTAssertNotNil(classNode);

    RLMInstanceTableViewController *controller = [self hostedControllerForClassNode:classNode];
    NSTableView *tableView = controller.tableView;

    // stringValue is editable; find its column.
    NSInteger column = [tableView columnWithIdentifier:@"stringValue"];
    XCTAssertGreaterThanOrEqual(column, 0);
    NSTableRowView *rowView = [tableView rowViewAtRow:2 makeIfNecessary:YES];
    XCTAssertTrue([rowView isKindOfClass:[RLMDrawnRowView class]]);

    [controller beginInlineEditingAtRow:2 column:column];
    XCTAssertTrue(controller.inlineEditingActive);

    NSTextField *field = controller.inlineEditorField;
    XCTAssertEqualObjects(field.superview, rowView, @"the editor is hosted by the row view");
    NSRect expected = [rowView convertRect:[tableView frameOfCellAtColumn:column row:2] fromView:tableView];
    XCTAssertTrue(NSEqualRects(field.frame, expected), @"editor covers just the edited cell, not the whole row");
    XCTAssertLessThan(NSWidth(field.frame), NSWidth(rowView.bounds));

    [controller discardInlineEditing];
    XCTAssertFalse(controller.inlineEditingActive);
    XCTAssertNil(field.superview);
}

#pragma mark - Drag image and accessibility

- (void)testDraggingImageIsASnapshotOfTheRow
{
    NSTableView *tableView = [self makeTableViewWithColumnCount:2 columnWidth:100.0];
    self.host.contentsByColumn = @[[RLMCellContent textContent:@"a" showsNilPlaceholder:NO],
                                   [RLMCellContent textContent:@"b" showsNilPlaceholder:NO]];
    RLMDrawnRowView *rowView = (RLMDrawnRowView *)[tableView rowViewAtRow:0 makeIfNecessary:YES];

    NSArray<NSDraggingImageComponent *> *components = rowView.draggingImageComponents;
    XCTAssertEqual(components.count, 1u);
    XCTAssertEqualObjects(components.firstObject.key, NSDraggingImageComponentIconKey);
    XCTAssertTrue([components.firstObject.contents isKindOfClass:[NSImage class]]);
    XCTAssertTrue(NSEqualSizes(components.firstObject.frame.size, rowView.bounds.size));
}

- (void)testAccessibilityChildrenDescribeVisibleColumns
{
    NSTableView *tableView = [self makeTableViewWithColumnCount:3 columnWidth:100.0];
    tableView.tableColumns[1].hidden = YES;
    tableView.tableColumns[0].title = @"name";
    tableView.tableColumns[2].title = @"done";
    self.host.contentsByColumn = @[[RLMCellContent textContent:@"Ada" showsNilPlaceholder:NO],
                                   [RLMCellContent textContent:@"hidden" showsNilPlaceholder:NO],
                                   [RLMCellContent boolContent:YES]];
    NSTableRowView *rowView = [tableView rowViewAtRow:0 makeIfNecessary:YES];

    NSArray *children = rowView.accessibilityChildren;
    XCTAssertEqual(children.count, 2u);
    NSAccessibilityElement *first = children[0];
    NSAccessibilityElement *second = children[1];
    XCTAssertEqualObjects(first.accessibilityLabel, @"name");
    XCTAssertEqualObjects(first.accessibilityValue, @"Ada");
    XCTAssertEqualObjects(second.accessibilityLabel, @"done");
    XCTAssertEqualObjects(second.accessibilityValue, @"true");
    XCTAssertEqual(first.accessibilityParent, rowView);
    XCTAssertTrue(NSEqualRects(first.accessibilityFrameInParentSpace,
                               [self cellRectOfRowView:rowView tableView:tableView column:0 row:0]));
}

@end
