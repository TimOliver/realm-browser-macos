# Drawn Row View Table Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make switching classes in the instance table feel instantaneous at any window size by replacing the one‑`NSTableCellView`‑per‑cell hierarchy with one `NSTableRowView` per row that draws every column itself.

**Architecture:** Keep `NSTableView`/`RLMTableView`, the column pool, navigation, selection, drag & drop, context menus and the header exactly as they are. `tableView:viewForTableColumn:row:` returns `nil`; `tableView:rowViewForRow:` returns a reusable `RLMDrawnRowView` that, in `drawRect:`, asks the controller for an `RLMCellContent` (kind + strings) per visible column and draws text / link / checkbox / badge directly. Navigation stops calling `reloadData` (which flushes NSTableView's reuse pool) and uses `noteNumberOfRowsChanged` + redraw; Realm change notifications redraw modified rows. The dead cell‑view classes are deleted.

**Tech Stack:** Objective‑C, AppKit (`NSTableRowView`, `NSStringDrawing`, `NSBezierPath`, `NSAccessibilityElement`), Realm 20.x via CocoaPods, XCTest, `xcodeproj` Ruby gem (already installed with CocoaPods) for project‑file edits.

**Spec:** The "Design" section directly below (distilled from the 2026‑08‑21 performance audit; there is no separate spec file).

## Global Constraints

- Deployment target macOS 11.0; ARC; everything Objective‑C with the `RLM` prefix; Apache license header block at the top of every new source file (copy it verbatim from `RealmBrowser/Views/RLMTableView.m` lines 1–17).
- Follow the Realm Objective‑C style guide and the surrounding code's conventions (see `CLAUDE.md`).
- Always build/test the **workspace** with the scheme name in quotes: `xcodebuild -workspace RealmBrowser.xcworkspace -scheme 'Realm Browser' -destination 'platform=macOS' test`.
- Do not touch the `Podfile` `post_install` hook.
- Never introduce an `NSControl` subclass (`NSButton`, `NSPopUpButton`, `NSTextField`…) as a persistent subview of a table row: on macOS 26 each one costs ≈1.3 ms to create/lay out. The only control allowed inside a row is the shared inline editor field while an edit is in progress.
- Never call `-[NSTableView reloadData]` on the navigation path (it purges the row/cell reuse pool); `reloadData` stays only for the ">200 changes" notification path.
- Do not modify the `RLMRealmBrowserWindowController` perf harness or any `RLM_PERF_*` experiment code — that lived in a scratch copy only and is **not** part of this repository.

---

## Design (what we are building and why)

### Measured problem (baseline, 65 rows × 20 columns = 1300 visible cells, macOS 26.6.2, Release)

| Phase of a class‑switch click | ≈ms | Cause |
|---|---|---|
| `performUpdateUsingState:` (sync) | 100 | `reloadData` teardown of 1300 cell views (~26); pooled‑column `setHidden:` walking live rows (~50, schema changes only); inspector rebuild (~9) |
| `-[NSTableView layout]` (row population) | 300 | Every cell view is **re‑created** — `reloadData` empties the reuse pool (`cellCreates == cellBinds` every click). `NSButton`/`NSPopUpButton` in bool/badge cells cost ≈1.3 ms each (SwiftUI‑backed sizing on macOS 26); `_setDefaultKeyViewLoop` per row forces a layout pass into those buttons |
| CA commit | 80–100 | 1300 layer‑backed cell views displayed individually |
| Binding code (Realm accessors, formatters, `setText:`) | ~4 | **Not** the problem |

Total ≈ 500 ms to a committed frame. A prototype with one row view drawing all its columns measured **36–50 ms** for the same click (zero cell views created, zero row views created after warm‑up), with the remaining time being string drawing + column auto‑fit measurement.

### Target architecture

```
RLMInstanceTableViewController (NSTableViewDataSource/Delegate, RLMDrawnRowViewDataSource)
   │  tableView:rowViewForRow:            → dequeues/creates RLMDrawnRowView (identifier RLMDrawnRowViewReuseIdentifier)
   │  tableView:viewForTableColumn:row:   → nil (no cell views, ever)
   │  rowView:contentForTableColumn:row:  → RLMCellContent (kind + text / boolValue / badgeText / placeholder flag)
   ▼
RLMDrawnRowView : NSTableRowView
   drawRect: → [super drawRect:] (background/selection) then for each non‑hidden column intersecting dirtyRect:
              cellRect = [self convertRect:[tableView frameOfCellAtColumn:c row:row] fromView:tableView]
              content  = [dataSource rowView:self contentForTableColumn:column row:row]
              draw by kind (Text / Link / Bool / Badge), emphasized colours when interiorBackgroundStyle == Emphasized
   row index is always looked up live via [tableView rowForView:self] (row views shift on insert/remove)
   draggingImageComponents → snapshot of self
   accessibilityChildren   → one NSAccessibilityElement per visible column
```

Behaviour mapping from today's cell views:

| Today | New |
|---|---|
| `RLMBasicTableCellView` / `RLMNumberTableCellView` drawn text, "nil" placeholder when optional | `RLMCellContentKindText`, `showsNilPlaceholder = property.optional` |
| `RLMLinkTableCellView` link colour + underline | `RLMCellContentKindLink` |
| `RLMBoolTableCellView` (disabled checkbox) | `RLMCellContentKindBool` → drawn rounded box + check mark |
| `RLMOptionalBoolTableCellView` (disabled popup nil/false/true) | `RLMCellContentKindText` with `"true"`/`"false"`, empty + placeholder for nil |
| `RLMBadgeTableCellView` (text + inline bezel count button) | `RLMCellContentKindBadge` → text + drawn count pill at trailing edge |
| Gutter column `#` (array index) | `RLMCellContentKindText` with the row number |
| Tooltip set on hovered cell view | Tooltip set on hovered **row view** (`rowViewAtRow:makeIfNecessary:NO`) |
| Inline editor added to the cell view | Inline editor added to the row view at the cell frame; edited row/column remembered in ivars |
| `reloadDataForRowIndexes:columnIndexes:` for modifications | `setNeedsDisplay:YES` on those row views (all rows when showing an array, because gutter indices shift) |
| `reloadData` in `setupColumnsWithType:` | `noteNumberOfRowsChanged` + redraw all row views |

### Files

Create:
- `RealmBrowser/Views/RLMCellContent.h` / `.m` — immutable value object describing one cell (kind, text, placeholder flag, bool value, badge text, spoken accessibility value).
- `RealmBrowser/Views/RLMDrawnRowView.h` / `.m` — the row view, its data‑source protocol, reuse identifier constant, shared text style (font / paragraph style / text height).
- `RealmBrowserTests/RLMDrawnRowViewTests.m` — tests for content mapping, drawing, redraw helpers, drag image, accessibility.

Modify:
- `RealmBrowser/Controllers/RLMInstanceTableViewController.m` — `rowViewForRow:`, `viewForTableColumn:row:`, new `rowView:contentForTableColumn:row:`, tooltips, inline editing, fine‑grained updates, imports.
- `RealmBrowser/Controllers/RLMInstanceTableViewController.h` — adopt `RLMDrawnRowViewDataSource`.
- `RealmBrowser/Views/RLMTableView.h` / `.m` — `redrawAllRows`, `redrawRowsAtIndexes:`, navigation reload strategy, redraw on column resize.
- `RealmBrowser/Models/RLMTableColumn.m`, `RealmBrowser/Support/RLMDescriptions.m` — drop imports of deleted headers.
- `RealmBrowser/Resources/UI/Base.lproj/RLMInstanceTableViewController.xib`, `RealmBrowser/Resources/UI/RLMObjectLinkSelectionViewController.xib` — `allowsExpansionToolTips` off.
- `RealmBrowser.xcodeproj/project.pbxproj` — via the `xcodeproj` gem (scripts inline below).

Delete (Task 7): `RealmBrowser/Views/RLMTableCellView.{h,m}`, `RLMBasicTableCellView.{h,m}`, `RLMNumberTableCellView.{h,m}`, `RLMLinkTableCellView.{h,m}`, `RLMBadgeTableCellView.{h,m}`, `RLMBoolTableCellView.{h,m}`, `RLMOptionalBoolTableCellView.{h,m}`, `RLMImageTableCellView.{h,m}`.

(`RLMSidebarTableCellView` and `RLMWelcomeRecentsCellView` are unrelated and stay.)

---

### Task 1: `RLMCellContent` value object (+ project scaffolding for all new files)

**Files:**
- Create: `RealmBrowser/Views/RLMCellContent.h`, `RealmBrowser/Views/RLMCellContent.m`
- Create (empty placeholders registered now, filled in Task 2): `RealmBrowser/Views/RLMDrawnRowView.h`, `RealmBrowser/Views/RLMDrawnRowView.m`
- Create: `RealmBrowserTests/RLMDrawnRowViewTests.m`
- Modify: `RealmBrowser.xcodeproj/project.pbxproj` (via script)

**Interfaces:**
- Produces:
  ```objc
  typedef NS_ENUM(NSInteger, RLMCellContentKind) { RLMCellContentKindText, RLMCellContentKindLink, RLMCellContentKindBool, RLMCellContentKindBadge };
  @interface RLMCellContent : NSObject
  @property (nonatomic, readonly) RLMCellContentKind kind;
  @property (nonatomic, readonly, copy) NSString *text;        // never nil (empty string when there is nothing to show)
  @property (nonatomic, readonly) BOOL showsNilPlaceholder;    // draw "nil" in placeholder colour when text is empty
  @property (nonatomic, readonly) BOOL boolValue;              // kind == Bool
  @property (nonatomic, readonly, copy) NSString *badgeText;   // kind == Badge; nil otherwise
  + (instancetype)textContent:(NSString *)text showsNilPlaceholder:(BOOL)placeholder;
  + (instancetype)linkContent:(NSString *)text;
  + (instancetype)boolContent:(BOOL)value;
  + (instancetype)badgeContent:(NSString *)text count:(NSUInteger)count;
  - (NSString *)accessibilityValueString;                      // what VoiceOver reads for this cell
  @end
  ```

- [ ] **Step 1: Create the files with license headers and register them in the Xcode project**

Create the five files. `RLMCellContent.h/.m` and `RLMDrawnRowView.h/.m` get the license block plus an `@import Cocoa;` line only for now; `RLMDrawnRowViewTests.m` gets the license block and this skeleton:

```objc
@import XCTest;
@import Cocoa;
@import Realm;

#import "RLMCellContent.h"

@interface RLMDrawnRowViewTests : XCTestCase
@end

@implementation RLMDrawnRowViewTests
@end
```

Register them (run from the repo root; `xcodeproj` is installed as a CocoaPods dependency):

```bash
ruby -e '
require "xcodeproj"
project = Xcodeproj::Project.open("RealmBrowser.xcodeproj")
app   = project.targets.find { |t| t.product_type == "com.apple.product-type.application" }
tests = project.targets.find { |t| t.product_type == "com.apple.product-type.bundle.unit-test" }
views = project.main_group.find_subpath("RealmBrowser/Views", false) or abort "Views group not found"
tests_group = project.main_group.find_subpath("RealmBrowserTests", false) or abort "RealmBrowserTests group not found"
%w[RLMCellContent RLMDrawnRowView].each do |base|
  views.new_file("#{base}.h")
  app.add_file_references([views.new_file("#{base}.m")])
end
tests.add_file_references([tests_group.new_file("RLMDrawnRowViewTests.m")])
project.save
puts "registered"
'
```

Verify: `grep -c "RLMCellContent.m in Sources\|RLMDrawnRowView.m in Sources\|RLMDrawnRowViewTests.m in Sources" RealmBrowser.xcodeproj/project.pbxproj` prints `3`.

- [ ] **Step 2: Write the failing tests for `RLMCellContent`**

Append to `RLMDrawnRowViewTests.m` inside the `@implementation`:

```objc
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `xcodebuild -workspace RealmBrowser.xcworkspace -scheme 'Realm Browser' -destination 'platform=macOS' test -only-testing:RealmBrowserTests/RLMDrawnRowViewTests 2>&1 | grep -E "error:|Test Case|\*\* TEST"`
Expected: build errors such as `no known class method for selector 'textContent:showsNilPlaceholder:'` (the test cannot compile yet).

- [ ] **Step 4: Implement `RLMCellContent`**

`RealmBrowser/Views/RLMCellContent.h` (below the license block):

```objc
@import Foundation;

typedef NS_ENUM(NSInteger, RLMCellContentKind) {
    RLMCellContentKindText,   // plain text (numbers, strings, dates, data, ids, optional bools, gutter index)
    RLMCellContentKindLink,   // link to another object: link colour + underline
    RLMCellContentKindBool,   // drawn checkbox
    RLMCellContentKindBadge,  // list property: text plus a count pill at the trailing edge
};

// Everything a row view needs to draw one cell. Built by the table view
// controller from the Realm value; contains no references to Realm objects.
@interface RLMCellContent : NSObject

@property (nonatomic, readonly) RLMCellContentKind kind;
@property (nonatomic, readonly, copy) NSString *text;       // never nil
@property (nonatomic, readonly) BOOL showsNilPlaceholder;   // draw "nil" when text is empty
@property (nonatomic, readonly) BOOL boolValue;             // kind == RLMCellContentKindBool
@property (nonatomic, readonly, copy) NSString *badgeText;  // kind == RLMCellContentKindBadge

+ (instancetype)textContent:(NSString *)text showsNilPlaceholder:(BOOL)placeholder;
+ (instancetype)linkContent:(NSString *)text;
+ (instancetype)boolContent:(BOOL)value;
+ (instancetype)badgeContent:(NSString *)text count:(NSUInteger)count;

// What accessibility clients read for this cell.
- (NSString *)accessibilityValueString;

@end
```

`RealmBrowser/Views/RLMCellContent.m`:

```objc
#import "RLMCellContent.h"

@implementation RLMCellContent

- (instancetype)initWithKind:(RLMCellContentKind)kind text:(NSString *)text placeholder:(BOOL)placeholder boolValue:(BOOL)boolValue badgeText:(NSString *)badgeText
{
    if (self = [super init]) {
        _kind = kind;
        _text = [text copy] ?: @"";
        _showsNilPlaceholder = placeholder;
        _boolValue = boolValue;
        _badgeText = [badgeText copy];
    }
    return self;
}

+ (instancetype)textContent:(NSString *)text showsNilPlaceholder:(BOOL)placeholder
{
    return [[self alloc] initWithKind:RLMCellContentKindText text:text placeholder:placeholder boolValue:NO badgeText:nil];
}

+ (instancetype)linkContent:(NSString *)text
{
    return [[self alloc] initWithKind:RLMCellContentKindLink text:text placeholder:NO boolValue:NO badgeText:nil];
}

+ (instancetype)boolContent:(BOOL)value
{
    return [[self alloc] initWithKind:RLMCellContentKindBool text:@"" placeholder:NO boolValue:value badgeText:nil];
}

+ (instancetype)badgeContent:(NSString *)text count:(NSUInteger)count
{
    return [[self alloc] initWithKind:RLMCellContentKindBadge text:text placeholder:NO boolValue:NO
                            badgeText:[NSString stringWithFormat:@"%lu", (unsigned long)count]];
}

- (NSString *)accessibilityValueString
{
    switch (self.kind) {
        case RLMCellContentKindBool:
            return self.boolValue ? @"true" : @"false";
        case RLMCellContentKindBadge:
            return [NSString stringWithFormat:@"%@, %@ %@", self.text, self.badgeText,
                    [self.badgeText isEqualToString:@"1"] ? @"item" : @"items"];
        case RLMCellContentKindText:
        case RLMCellContentKindLink:
            if (self.text.length == 0 && self.showsNilPlaceholder) {
                return @"nil";
            }
            return self.text;
    }
}

@end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: same command as Step 3.
Expected: `Test Case '-[RLMDrawnRowViewTests testTextContentKeepsTextAndPlaceholderFlag]' passed` (and the other two), `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add RealmBrowser/Views/RLMCellContent.h RealmBrowser/Views/RLMCellContent.m RealmBrowser/Views/RLMDrawnRowView.h RealmBrowser/Views/RLMDrawnRowView.m RealmBrowserTests/RLMDrawnRowViewTests.m RealmBrowser.xcodeproj/project.pbxproj
git commit -m "Add RLMCellContent value object and register drawn-row-view sources"
```

---

### Task 2: `RLMDrawnRowView` draws every column of its row

**Files:**
- Modify: `RealmBrowser/Views/RLMDrawnRowView.h`, `RealmBrowser/Views/RLMDrawnRowView.m` (fill in the placeholders from Task 1)
- Test: `RealmBrowserTests/RLMDrawnRowViewTests.m`

**Interfaces:**
- Consumes: `RLMCellContent` (Task 1).
- Produces:
  ```objc
  extern NSString * const RLMDrawnRowViewReuseIdentifier;   // @"RLMDrawnRowView"
  @protocol RLMDrawnRowViewDataSource <NSObject>
  - (RLMCellContent *)rowView:(RLMDrawnRowView *)rowView contentForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;
  @end
  @interface RLMDrawnRowView : NSTableRowView
  @property (nonatomic, weak) NSTableView *tableView;
  @property (nonatomic, weak) id<RLMDrawnRowViewDataSource> contentDataSource;
  + (NSFont *)cellTextFont;          // monospacedDigitSystemFontOfSize:12 weight:Regular (same as the old cells and RLMTableColumn measurement)
  + (CGFloat)cellTextHeight;
  @end
  ```

- [ ] **Step 1: Write the failing drawing tests (with an offscreen table fixture)**

Add to the top of `RLMDrawnRowViewTests.m` (after the imports): `#import "RLMDrawnRowView.h"`, then this fixture and helpers **before** `@interface RLMDrawnRowViewTests`:

```objc
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
```

Add these ivars/helpers to the test class (replace the empty `@interface RLMDrawnRowViewTests : XCTestCase @end` with):

```objc
@interface RLMDrawnRowViewTests : XCTestCase
@property (nonatomic, strong) NSWindow *window;          // keeps the offscreen view hierarchy alive
@property (nonatomic, strong) RLMDrawnRowViewTestHost *host;
@end
```

and inside the `@implementation`:

```objc
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
    NSTableView *tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -workspace RealmBrowser.xcworkspace -scheme 'Realm Browser' -destination 'platform=macOS' test -only-testing:RealmBrowserTests/RLMDrawnRowViewTests 2>&1 | grep -E "error:|Test Case|\*\* TEST"`
Expected: compile errors (`RLMDrawnRowView` / `RLMDrawnRowViewReuseIdentifier` undeclared).

- [ ] **Step 3: Implement `RLMDrawnRowView`**

`RealmBrowser/Views/RLMDrawnRowView.h` (below the license block):

```objc
@import Cocoa;

@class RLMCellContent;
@class RLMDrawnRowView;

// Reuse identifier for -[NSTableView makeViewWithIdentifier:owner:].
extern NSString * const RLMDrawnRowViewReuseIdentifier;

@protocol RLMDrawnRowViewDataSource <NSObject>

// Content of one cell. Called during drawing for every visible column of a row, so it
// must be cheap (read the value, format it); return nil to draw nothing.
- (RLMCellContent *)rowView:(RLMDrawnRowView *)rowView contentForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;

@end

// One view per row that draws every column itself. The table hosts no cell views at all,
// which is what keeps populating a screenful of rows cheap: the per-view overhead of
// AppKit (layout engine, key view loop, layer commit) is paid per row, not per cell.
@interface RLMDrawnRowView : NSTableRowView

@property (nonatomic, weak) NSTableView *tableView;
@property (nonatomic, weak) id<RLMDrawnRowViewDataSource> contentDataSource;

// Shared text style, also used by RLMTableColumn to measure content widths.
+ (NSFont *)cellTextFont;
+ (CGFloat)cellTextHeight;

@end
```

`RealmBrowser/Views/RLMDrawnRowView.m`:

```objc
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: same command as Step 2.
Expected: all `RLMDrawnRowViewTests` pass. If `testRowViewDrawsTextOnlyInColumnsThatHaveContent` fails on the "empty column draws nothing" assertion, check that the table's grid style is none (the fixture uses a plain `NSTableView`, no grid) and that `[super drawRect:]` paints a uniform background (it does for unselected rows).

- [ ] **Step 5: Commit**

```bash
git add RealmBrowser/Views/RLMDrawnRowView.h RealmBrowser/Views/RLMDrawnRowView.m RealmBrowserTests/RLMDrawnRowViewTests.m
git commit -m "Add RLMDrawnRowView: one row view draws every column"
```

---

### Task 3: Controller serves `RLMCellContent` and uses row views instead of cell views

**Files:**
- Modify: `RealmBrowser/Controllers/RLMInstanceTableViewController.h` (adopt the protocol)
- Modify: `RealmBrowser/Controllers/RLMInstanceTableViewController.m` — imports (lines 31–36), `tableView:rowViewForRow:` (≈285–297), `tableView:viewForTableColumn:row:` (≈435–583)
- Test: `RealmBrowserTests/RLMDrawnRowViewTests.m`

**Interfaces:**
- Consumes: `RLMDrawnRowView`, `RLMDrawnRowViewReuseIdentifier`, `RLMDrawnRowViewDataSource`, `RLMCellContent` (Tasks 1–2); `RLMTableColumn.classProperty` / `RLMClassProperty.property` (existing); `RLMDescriptions printablePropertyValue:ofType:` (existing); `RLMTypeNode instanceAtIndex:` (existing).
- Produces: `- (RLMCellContent *)rowView:(RLMDrawnRowView *)rowView contentForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;` on `RLMInstanceTableViewController` (public through the protocol conformance).

- [ ] **Step 1: Write the failing content-mapping test**

The test target is hosted inside the app (`TEST_HOST`), so app classes, nibs and `RealmTestClass1` (from `RealmBrowser/Support/TestClasses.h`, generated by `RLMTestDataGenerator`) are available. Add to the test file imports:

```objc
#import "RLMInstanceTableViewController.h"
#import "RLMRealmNode.h"
#import "RLMClassNode.h"
#import "RLMTableColumn.h"
#import "RLMClassProperty.h"
#import "RLMTestDataGenerator.h"
#import "TestClasses.h"
```

and this test inside the implementation:

```objc
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
    XCTAssertTrue([RLMTestDataGenerator createRealmAtUrl:fileURL withClassesNamed:@[[RealmTestClass1 className]] objectCount:3 encryptionKey:nil]);

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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -workspace RealmBrowser.xcworkspace -scheme 'Realm Browser' -destination 'platform=macOS' test -only-testing:RealmBrowserTests/RLMDrawnRowViewTests/testControllerMapsPropertyTypesToCellContent 2>&1 | grep -E "error:|Test Case|\*\* TEST"`
Expected: compile error — `RLMInstanceTableViewController` has no method `rowView:contentForTableColumn:row:`.

- [ ] **Step 3: Adopt the protocol in the header**

In `RLMInstanceTableViewController.h`, add `#import "RLMDrawnRowView.h"` after `#import "RLMTableView.h"` and change the interface line to:

```objc
@interface RLMInstanceTableViewController : RLMViewController <RLMTableViewDelegate, RLMTableViewDataSource, RLMDrawnRowViewDataSource>
```

- [ ] **Step 4: Replace the cell-view code in the controller**

In `RLMInstanceTableViewController.m`:

1. Replace the six cell-view imports (lines 31–36, `RLMBadgeTableCellView.h` … `RLMImageTableCellView.h`) with:

```objc
#import "RLMDrawnRowView.h"
#import "RLMCellContent.h"
```

2. Replace the whole `tableView:rowViewForRow:` method with:

```objc
- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row
{
    // The table hosts no cell views: each row view draws all of its columns itself
    // (see RLMDrawnRowView). Row views are recycled through the table's reuse queue.
    RLMDrawnRowView *rowView = [tableView makeViewWithIdentifier:RLMDrawnRowViewReuseIdentifier owner:self];
    if (rowView == nil) {
        rowView = [[RLMDrawnRowView alloc] initWithFrame:NSZeroRect];
        rowView.identifier = RLMDrawnRowViewReuseIdentifier;
    }
    rowView.tableView = tableView;
    rowView.contentDataSource = self;
    [rowView setNeedsDisplay:YES];
    return rowView;
}
```

3. Replace the whole `tableView:viewForTableColumn:row:` method (the big `switch`, ≈ lines 435–583) with these two methods:

```objc
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
    // No cell views — RLMDrawnRowView draws every column (see rowView:contentForTableColumn:row:).
    return nil;
}

#pragma mark - RLMDrawnRowViewDataSource

- (RLMCellContent *)rowView:(RLMDrawnRowView *)rowView contentForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
    if (![tableColumn isKindOfClass:[RLMTableColumn class]]) {
        return nil;
    }
    RLMClassProperty *classProperty = [(RLMTableColumn *)tableColumn classProperty];

    // Array gutter (the only column with no backing property)
    if (classProperty == nil) {
        return [RLMCellContent textContent:[@(rowIndex) stringValue] showsNilPlaceholder:NO];
    }
    if (rowIndex < 0 || (NSUInteger)rowIndex >= self.displayedType.instanceCount) {
        return nil;
    }

    RLMProperty *property = classProperty.property;
    RLMObject *instance = [self.displayedType instanceAtIndex:(NSUInteger)rowIndex];
    id propertyValue = instance[classProperty.name];
    if (propertyValue == NSNull.null) {
        propertyValue = nil;
    }

    if (property.array) {
        return [RLMCellContent badgeContent:[realmDescriptions printablePropertyValue:propertyValue ofType:property]
                                      count:[(RLMArray *)propertyValue count]];
    }

    switch (classProperty.type) {
        case RLMPropertyTypeBool:
            if (property.optional) {
                // Mirrors the old nil / false / true popup, as text.
                NSString *text = (propertyValue == nil) ? @"" : ([propertyValue boolValue] ? @"true" : @"false");
                return [RLMCellContent textContent:text showsNilPlaceholder:YES];
            }
            return [RLMCellContent boolContent:[(NSNumber *)propertyValue boolValue]];

        case RLMPropertyTypeObject:
            return [RLMCellContent linkContent:[realmDescriptions printablePropertyValue:propertyValue ofType:property]];

        case RLMPropertyTypeInt:
        case RLMPropertyTypeFloat:
        case RLMPropertyTypeDouble:
        case RLMPropertyTypeLinkingObjects:
        case RLMPropertyTypeData:
        case RLMPropertyTypeAny:
        case RLMPropertyTypeDate:
        case RLMPropertyTypeString:
        case RLMPropertyTypeObjectId:
        case RLMPropertyTypeDecimal128:
        case RLMPropertyTypeUUID:
            return [RLMCellContent textContent:[realmDescriptions printablePropertyValue:propertyValue ofType:property]
                            showsNilPlaceholder:property.optional];
    }
}
```

(`realmDescriptions` is the existing ivar created in `awakeFromNib`.) Delete the now-unused `#import "objc/objc-class.h"` only if the compiler reports nothing else uses it — it does not; remove it.

- [ ] **Step 5: Build and run the new test**

Run: same command as Step 2.
Expected: `testControllerMapsPropertyTypesToCellContent` passes. Also run the full suite: `xcodebuild -workspace RealmBrowser.xcworkspace -scheme 'Realm Browser' -destination 'platform=macOS' test 2>&1 | grep -E "error:|failed|\*\* TEST"` → `** TEST SUCCEEDED **`.

- [ ] **Step 6: Smoke-run the app**

Run: `xcodebuild -workspace RealmBrowser.xcworkspace -scheme 'Realm Browser' -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"` then `open -a "$(xcodebuild -workspace RealmBrowser.xcworkspace -scheme 'Realm Browser' -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/{print $3}')/Realm Browser.app"`. Generate a demo database (Tools menu), open it, click through the three classes. Expected: values, checkboxes, link-coloured object columns, list badges with counts, "nil" placeholders and selection colours all render; no console errors. (Tooltips and inline editing are restored in Task 5.)

- [ ] **Step 7: Commit**

```bash
git add RealmBrowser/Controllers/RLMInstanceTableViewController.h RealmBrowser/Controllers/RLMInstanceTableViewController.m RealmBrowserTests/RLMDrawnRowViewTests.m
git commit -m "Serve RLMCellContent from the table controller; drop per-cell views"
```

---

### Task 4: Navigation and change notifications redraw rows instead of reloading

**Files:**
- Modify: `RealmBrowser/Views/RLMTableView.h` (public interface), `RealmBrowser/Views/RLMTableView.m` — `setupColumnsWithType:` (two `[self reloadData]` calls, ≈ lines 490 and 568), `columnDidResize:` (≈ line 587), nil guards around `removeTrackingArea:` in `dealloc` (≈ 79) and `updateTrackingAreas` (≈ 446)
- Modify: `RealmBrowser/Controllers/RLMInstanceTableViewController.m` — `displayedCollectionDidChange:error:` (≈ lines 215–263)
- Test: `RealmBrowserTests/RLMDrawnRowViewTests.m`

**Interfaces:**
- Produces on `RLMTableView`:
  ```objc
  - (void)redrawAllRows;                          // setNeedsDisplay:YES on every available row view
  - (void)redrawRowsAtIndexes:(NSIndexSet *)rows; // same for the given rows only (rows without a view are ignored)
  ```

- [ ] **Step 1: Write the failing tests for the redraw helpers**

Add `#import "RLMTableView.h"` to the test imports. The fixture from Task 2 creates a plain `NSTableView`; give it a class parameter. Change `makeTableViewWithColumnCount:columnWidth:` to create `[[RLMTableView alloc] initWithFrame:scrollView.bounds]` instead of `[[NSTableView alloc] …]` (RLMTableView's `awakeFromNib` is not run for programmatic instances; that is fine here) and add:

```objc
#pragma mark - Redraw helpers

- (void)testRedrawHelpersMarkOnlyTheRequestedRowViews
{
    RLMTableView *tableView = (RLMTableView *)[self makeTableViewWithColumnCount:1 columnWidth:100.0];
    [tableView rowViewAtRow:0 makeIfNecessary:YES];
    [tableView rowViewAtRow:1 makeIfNecessary:YES];
    [tableView rowViewAtRow:2 makeIfNecessary:YES];
    // The window is offscreen, so clear the flags by hand rather than relying on a display pass.
    [tableView enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *rowView, NSInteger row) {
        rowView.needsDisplay = NO;
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -workspace RealmBrowser.xcworkspace -scheme 'Realm Browser' -destination 'platform=macOS' test -only-testing:RealmBrowserTests/RLMDrawnRowViewTests/testRedrawHelpersMarkOnlyTheRequestedRowViews 2>&1 | grep -E "error:|Test Case|\*\* TEST"`
Expected: compile error — `redrawRowsAtIndexes:` / `redrawAllRows` not declared.

- [ ] **Step 3: Add the helpers to `RLMTableView`**

`RLMTableView.h`, inside the `@interface RLMTableView` block after `sizeColumnsToFitOnscreenContents`:

```objc
// Rows draw their own content (RLMDrawnRowView), so data changes are surfaced by
// redrawing row views rather than reloading cell views.
- (void)redrawAllRows;
- (void)redrawRowsAtIndexes:(NSIndexSet *)rows;
```

`RLMTableView.m`, in the `#pragma mark - Public Methods` section:

```objc
- (void)redrawAllRows
{
    [self enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *rowView, NSInteger row) {
        [rowView setNeedsDisplay:YES];
    }];
}

- (void)redrawRowsAtIndexes:(NSIndexSet *)rows
{
    NSInteger rowCount = self.numberOfRows;
    [rows enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
        if ((NSInteger)row < rowCount) {
            [[self rowViewAtRow:(NSInteger)row makeIfNecessary:NO] setNeedsDisplay:YES];
        }
    }];
}
```

The tests create `RLMTableView` programmatically, so `awakeFromNib` never runs and `trackingArea` is nil; guard the two places that remove it (`dealloc`, ≈ line 79, and `updateTrackingAreas`, ≈ line 446):

```objc
    if (trackingArea != nil) {
        [self removeTrackingArea:trackingArea];
    }
```

- [ ] **Step 4: Use them on the navigation path, on column resize, and for modifications**

`RLMTableView.m`, `setupColumnsWithType:` — replace **both** `[self reloadData];` calls (the one in the same-signature early-return branch and the one after `[self endUpdates];`) with:

```objc
    // Not reloadData: that purges the row reuse pool, and the rows would all be
    // rebuilt. The row count is updated and every visible row redraws its content.
    [self noteNumberOfRowsChanged];
    [self redrawAllRows];
```

`RLMTableView.m`, `columnDidResize:` — text positions depend on column widths, so add a redraw:

```objc
- (void)columnDidResize:(NSNotification *)notification
{
    [self updateHeaderToolTipRects];
    [self redrawAllRows];
}
```

`RLMInstanceTableViewController.m`, `displayedCollectionDidChange:error:` — replace the `reloadDataForRowIndexes:columnIndexes:` call inside the `beginUpdates`/`endUpdates` block. The block becomes:

```objc
            [tableView beginUpdates];
            [tableView removeRowsAtIndexes:deletions withAnimation:NSTableViewAnimationEffectNone];
            [tableView insertRowsAtIndexes:insertions withAnimation:NSTableViewAnimationEffectNone];
            [tableView endUpdates];
            // Row views draw their own content: redraw the modified rows. In array
            // mode the gutter shows indexes, which shift on insert/remove.
            if (self.displaysArray && (deletions.count > 0 || insertions.count > 0)) {
                [self.realmTableView redrawAllRows];
            }
            else {
                [self.realmTableView redrawRowsAtIndexes:modifications];
            }
            [self updateStatusLabel];
```

Leave `[self reloadData]` for the `totalChanges > 200` branch and the public `reloadData` method unchanged.

- [ ] **Step 5: Run the tests**

Run: `xcodebuild -workspace RealmBrowser.xcworkspace -scheme 'Realm Browser' -destination 'platform=macOS' test 2>&1 | grep -E "error:|failed|\*\* TEST"`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Manual check of the live-update path**

Build and run (as in Task 3 Step 6), open the demo database, select a class, then from a second window of the same file (File ▸ New Window, or the array "Open in new window" context item) edit a value: double-click a string cell in one window, type, press return. Expected: the other window's row repaints with the new value without the whole table flashing; adding objects (Edit ▸ Add new object) inserts a row and scrolls to it; deleting removes it. Navigating between classes shows correct data and the correct row count in the status label.

- [ ] **Step 7: Commit**

```bash
git add RealmBrowser/Views/RLMTableView.h RealmBrowser/Views/RLMTableView.m RealmBrowser/Controllers/RLMInstanceTableViewController.m RealmBrowserTests/RLMDrawnRowViewTests.m
git commit -m "Redraw row views on navigation, column resize and data changes instead of reloading"
```

---

### Task 5: Tooltips and inline editing target the row view

**Files:**
- Modify: `RealmBrowser/Controllers/RLMInstanceTableViewController.m` — ivars (≈ lines 66–74), `mouseDidEnterCellAtLocation:` (≈ 1037–1067), `beginInlineEditingAtRow:column:` (≈ 1215–1260), `inlineEditorAction:` (≈ 1284–1355)

**Interfaces:**
- Consumes: `-[NSTableView rowViewAtRow:makeIfNecessary:]`, `-[NSTableView frameOfCellAtColumn:row:]` (AppKit).

- [ ] **Step 1: Tooltips on the hovered row view**

In `mouseDidEnterCellAtLocation:` replace

```objc
    NSView *hoveredCellView = [self.tableView viewAtColumn:location.column row:location.row makeIfNecessary:NO];
    if (hoveredCellView) {
        hoveredCellView.toolTip = [realmDescriptions tooltipForPropertyValue:propertyValue ofType:propertyNode.property];
    }
```

with

```objc
    // There are no cell views; the tooltip is set on the hovered row view and
    // replaced as the mouse moves between that row's cells.
    NSTableRowView *hoveredRowView = [self.tableView rowViewAtRow:location.row makeIfNecessary:NO];
    hoveredRowView.toolTip = [realmDescriptions tooltipForPropertyValue:propertyValue ofType:propertyNode.property];
```

and in `mouseDidExitCellAtLocation:` add, before `[self disableLinkCursor];`:

```objc
    if (location.row >= 0) {
        [self.tableView rowViewAtRow:location.row makeIfNecessary:NO].toolTip = nil;
    }
```

- [ ] **Step 2: Inline editor overlays the row view at the cell frame**

Add two ivars to the `@implementation RLMInstanceTableViewController { … }` block:

```objc
    NSInteger inlineEditingRow;
    NSInteger inlineEditingColumn;
```

and initialise them in `awakeFromNib` next to `pendingScrollRow = NOT_A_ROW;`:

```objc
    inlineEditingRow = NOT_A_ROW;
    inlineEditingColumn = NOT_A_COLUMN;
```

In `beginInlineEditingAtRow:column:` replace

```objc
    NSView *cellView = [self.tableView viewAtColumn:column row:row makeIfNecessary:NO];
    if (cellView == nil) {
        return;
    }
```

with

```objc
    NSTableRowView *rowView = [self.tableView rowViewAtRow:row makeIfNecessary:NO];
    if (rowView == nil) {
        return;
    }
```

and replace

```objc
    field.frame = cellView.bounds;
    [cellView addSubview:field];
```

with

```objc
    field.frame = [rowView convertRect:[self.tableView frameOfCellAtColumn:column row:row] fromView:self.tableView];
    [rowView addSubview:field];
    inlineEditingRow = row;
    inlineEditingColumn = column;
```

In `inlineEditorAction:` replace

```objc
    NSInteger row = [self.tableView rowForView:sender];
    NSInteger column = [self.tableView columnForView:sender];
```

with

```objc
    // The editor is a direct subview of the row view, so columnForView: cannot
    // recover the column; both were recorded when editing began.
    NSInteger row = inlineEditingRow;
    NSInteger column = inlineEditingColumn;
    inlineEditingRow = NOT_A_ROW;
    inlineEditingColumn = NOT_A_COLUMN;
```

In `discardInlineEditing`, after `self.inlineEditingActive = NO;` add:

```objc
    inlineEditingRow = NOT_A_ROW;
    inlineEditingColumn = NOT_A_COLUMN;
```

- [ ] **Step 3: Build, run tests, verify manually**

Run: `xcodebuild -workspace RealmBrowser.xcworkspace -scheme 'Realm Browser' -destination 'platform=macOS' test 2>&1 | grep -E "error:|failed|\*\* TEST"` → `** TEST SUCCEEDED **`.

Then run the app with the demo database and check:
- Hover a string cell → after a moment a tooltip shows the (long) string; hover an object-link cell → multi-line object description; hover an array cell → list summary; moving to the next cell in the same row updates the tooltip.
- Double-click a string or number cell → the editor appears exactly over the cell (not over the whole row), typing + Return commits (value changes, row redraws), Escape cancels, clicking elsewhere commits; primary-key and bool/date/link cells do not enter editing.
- Pointing-hand cursor still appears over link and array cells; single-clicking an object link navigates to it; single-clicking an array navigates into it; the back button returns.

- [ ] **Step 4: Commit**

```bash
git add RealmBrowser/Controllers/RLMInstanceTableViewController.m
git commit -m "Point tooltips and the inline editor at row views"
```

---

### Task 6: Drag image and accessibility for drawn rows

**Files:**
- Modify: `RealmBrowser/Views/RLMDrawnRowView.m`
- Test: `RealmBrowserTests/RLMDrawnRowViewTests.m`

**Interfaces:**
- Consumes: `RLMCellContent accessibilityValueString` (Task 1).
- Produces: `-[RLMDrawnRowView draggingImageComponents]` (one `NSDraggingImageComponent` snapshot), `-[RLMDrawnRowView accessibilityChildren]` (one `NSAccessibilityElement` per non-hidden column).

- [ ] **Step 1: Write the failing tests**

```objc
#pragma mark - Drag image and accessibility

- (void)testDraggingImageIsASnapshotOfTheRow
{
    NSTableView *tableView = [self makeTableViewWithColumnCount:2 columnWidth:100.0];
    self.host.contentsByColumn = @[[RLMCellContent textContent:@"a" showsNilPlaceholder:NO],
                                   [RLMCellContent textContent:@"b" showsNilPlaceholder:NO]];
    NSTableRowView *rowView = [tableView rowViewAtRow:0 makeIfNecessary:YES];

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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -workspace RealmBrowser.xcworkspace -scheme 'Realm Browser' -destination 'platform=macOS' test -only-testing:RealmBrowserTests/RLMDrawnRowViewTests 2>&1 | grep -E "error:|Test Case|\*\* TEST"`
Expected: `testDraggingImageIsASnapshotOfTheRow` fails (default `draggingImageComponents` of a row with no cell views is empty) and `testAccessibilityChildrenDescribeVisibleColumns` fails (`children.count` is 0).

- [ ] **Step 3: Implement both on `RLMDrawnRowView`**

Add to `RLMDrawnRowView.m` before `@end`:

```objc
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
        NSAccessibilityElement *element = [NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityCellRole
                                                                                        frame:cellRect
                                                                                        label:column.title
                                                                                       parent:self];
        element.accessibilityValue = [content accessibilityValueString] ?: @"";
        [children addObject:element];
    }
    return children;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: same command as Step 2. Expected: all `RLMDrawnRowViewTests` pass.

- [ ] **Step 5: Manual check**

Run the app, open an array (click an array badge cell), drag a row to another position: a drag image showing the row's text appears and the move is applied. With VoiceOver on (⌘F5), focus the table and use VO+→ across a row: each cell is read as "<column title>, <value>".

- [ ] **Step 6: Commit**

```bash
git add RealmBrowser/Views/RLMDrawnRowView.m RealmBrowserTests/RLMDrawnRowViewTests.m
git commit -m "Drag image snapshot and accessibility children for drawn row views"
```

---

### Task 7: Remove the dead cell-view classes, unused imports and expansion tooltips

**Files:**
- Delete: `RealmBrowser/Views/RLMTableCellView.{h,m}`, `RLMBasicTableCellView.{h,m}`, `RLMNumberTableCellView.{h,m}`, `RLMLinkTableCellView.{h,m}`, `RLMBadgeTableCellView.{h,m}`, `RLMBoolTableCellView.{h,m}`, `RLMOptionalBoolTableCellView.{h,m}`, `RLMImageTableCellView.{h,m}`
- Modify: `RealmBrowser/Models/RLMTableColumn.m` (line 20 import; `measurementAttributes`), `RealmBrowser/Support/RLMDescriptions.m` (lines 27–31 imports), both XIBs, `RealmBrowser.xcodeproj/project.pbxproj` (via script)

- [ ] **Step 1: Confirm nothing else references the classes**

Run: `grep -rn "RLMTableCellView\|RLMBasicTableCellView\|RLMNumberTableCellView\|RLMLinkTableCellView\|RLMBadgeTableCellView\|RLMBoolTableCellView\|RLMOptionalBoolTableCellView\|RLMImageTableCellView" RealmBrowser RealmBrowserTests --include='*.m' --include='*.h' --include='*.xib' | grep -v "^RealmBrowser/Views/RLM[A-Za-z]*TableCellView\.[mh]:"`
Expected: only the import lines in `RLMTableColumn.m` and `RLMDescriptions.m` (Task 3 already removed the controller's). If anything else shows up, stop and fix that first.

- [ ] **Step 2: Fix the two importers**

`RLMTableColumn.m`: replace `#import "RLMTableCellView.h"` with `#import "RLMDrawnRowView.h"` and make `measurementAttributes` use the shared font so measurement and drawing can never drift:

```objc
+ (NSDictionary *)measurementAttributes
{
    static NSDictionary *textAttributes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        textAttributes = @{NSFontAttributeName: [RLMDrawnRowView cellTextFont]};
    });
    return textAttributes;
}
```

`RLMDescriptions.m`: delete the five `#import "RLM…TableCellView.h"` lines (27–31).

- [ ] **Step 3: Delete the files and their project references**

```bash
ruby -e '
require "xcodeproj"
names = %w[RLMTableCellView RLMBasicTableCellView RLMNumberTableCellView RLMLinkTableCellView RLMBadgeTableCellView RLMBoolTableCellView RLMOptionalBoolTableCellView RLMImageTableCellView]
project = Xcodeproj::Project.open("RealmBrowser.xcodeproj")
refs = project.files.select { |f| f.path && names.any? { |n| File.basename(f.path) == "#{n}.h" || File.basename(f.path) == "#{n}.m" } }
abort "expected 16 refs, found #{refs.count}" unless refs.count == 16
refs.each(&:remove_from_project)
project.save
puts "removed #{refs.count} references"
'
git rm RealmBrowser/Views/RLM{,Basic,Number,Link,Badge,Bool,OptionalBool,Image}TableCellView.{h,m}
```

Verify: `grep -c "TableCellView" RealmBrowser.xcodeproj/project.pbxproj` now counts only `RLMSidebarTableCellView` and `RLMWelcomeRecentsCellView` entries (run `grep "TableCellView" RealmBrowser.xcodeproj/project.pbxproj | grep -v "Sidebar\|WelcomeRecents"` → no output).

- [ ] **Step 4: Turn off expansion tooltips in both table XIBs**

Expansion tooltips only work with cell views and install per-cell tracking. In `RealmBrowser/Resources/UI/Base.lproj/RLMInstanceTableViewController.xib` and `RealmBrowser/Resources/UI/RLMObjectLinkSelectionViewController.xib` remove the attribute `allowsExpansionToolTips="YES"` from the `<tableView … customClass="RLMTableView">` element (`sed -i '' 's/ allowsExpansionToolTips="YES"//' <file>` on each). Verify: `grep -c allowsExpansionToolTips` on both files prints `0`.

- [ ] **Step 5: Build everything and run the full test suite**

Run: `xcodebuild -workspace RealmBrowser.xcworkspace -scheme 'Realm Browser' -destination 'platform=macOS' test 2>&1 | grep -E "error:|warning: .*RLM|failed|\*\* TEST"`
Expected: no errors, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add -A RealmBrowser/Views RealmBrowser/Models/RLMTableColumn.m RealmBrowser/Support/RLMDescriptions.m RealmBrowser/Resources/UI RealmBrowser.xcodeproj/project.pbxproj
git commit -m "Remove unused table cell view classes and expansion tooltips"
```

---

### Task 8: End-to-end verification and performance measurement

**Files:** none modified (measurement only). If a regression is found, fix it in the task that owns that code and re-run.

- [ ] **Step 1: Generate a wide, large realm to test with**

The built-in demo database is small (1000 rows, ≤7 columns). Build the generator below against the Realm framework that CocoaPods built (adjust `$DD` to your DerivedData products directory, e.g. `~/Library/Developer/Xcode/DerivedData/RealmBrowser-*/Build/Products/Debug`):

```bash
DD=$(xcodebuild -workspace RealmBrowser.xcworkspace -scheme 'Realm Browser' -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/{print $3}')
mkdir -p /tmp/rlmperf && cat > /tmp/rlmperf/gen.m <<'EOF'
@import Foundation;
@import Realm;
@interface Tiny : RLMObject
@property int tid; @property NSString *label;
@end
@implementation Tiny
+ (NSString *)primaryKey { return @"tid"; }
@end
RLM_COLLECTION_TYPE(Tiny)
#define WIDE_PROPS @property int wid; @property NSString *name; @property NSString *email; @property NSString *city; @property NSString *notes; \
@property int a; @property int b; @property int c; @property int d; @property int e; @property int f; @property double x; @property double y; @property double z; \
@property BOOL flag1; @property BOOL flag2; @property NSDate *created; @property Tiny *owner; @property RLMArray<Tiny> *tags; @property NSNumber<RLMInt> *optInt;
@interface Wide : RLMObject
WIDE_PROPS
@end
@implementation Wide
+ (NSString *)primaryKey { return @"wid"; }
@end
@interface Wide2 : RLMObject
WIDE_PROPS
@end
@implementation Wide2
+ (NSString *)primaryKey { return @"wid"; }
@end
@interface Narrow : RLMObject
@property int nid; @property NSString *title; @property double score; @property BOOL done; @property NSDate *when;
@end
@implementation Narrow
+ (NSString *)primaryKey { return @"nid"; }
@end
static NSString *randWord(NSUInteger len) { char buf[64]; for (NSUInteger i = 0; i < len; i++) buf[i] = 'a' + arc4random_uniform(26); buf[len] = 0; return @(buf); }
int main(int argc, const char *argv[]) { @autoreleasepool {
    NSString *path = @(argv[1]); NSUInteger rows = (NSUInteger)atol(argv[2]);
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    RLMRealmConfiguration *config = [RLMRealmConfiguration new]; config.fileURL = [NSURL fileURLWithPath:path];
    RLMRealm *realm = [RLMRealm realmWithConfiguration:config error:nil];
    NSMutableArray *tinies = [NSMutableArray array];
    [realm transactionWithBlock:^{ for (int i = 0; i < 5000; i++) [tinies addObject:[Tiny createInRealm:realm withValue:@[@(i), randWord(8)]]]; }];
    for (NSString *cls in @[@"Wide", @"Wide2"]) { Class klass = NSClassFromString(cls);
        for (NSUInteger base = 0; base < rows; base += 20000) { @autoreleasepool { [realm transactionWithBlock:^{
            for (NSUInteger i = base; i < MIN(rows, base + 20000); i++) {
                NSMutableArray *tags = [NSMutableArray array]; for (NSUInteger k = 0, n = arc4random_uniform(4); k < n; k++) [tags addObject:tinies[arc4random_uniform(5000)]];
                [klass createInRealm:realm withValue:@[@((int)i), randWord(9), [randWord(7) stringByAppendingString:@"@x.com"], randWord(8), (i % 3 == 0) ? @"" : randWord(20),
                    @((int)arc4random()), @((int)arc4random_uniform(1000)), @((int)arc4random_uniform(10)), @((int)arc4random()), @((int)arc4random_uniform(100000)), @((int)arc4random_uniform(2)),
                    @(arc4random() / (double)UINT32_MAX * 1000.0), @(arc4random() / (double)UINT32_MAX), @((double)i * 0.5), @(i % 2 == 0), @(i % 3 == 0),
                    [NSDate dateWithTimeIntervalSince1970:1.0e9 + i * 37.0], (i % 7 == 0) ? NSNull.null : tinies[arc4random_uniform(5000)], tags,
                    (i % 5 == 0) ? NSNull.null : @((int)arc4random_uniform(100000))]];
            } }]; } } }
    [realm transactionWithBlock:^{ for (NSUInteger i = 0; i < rows; i++) [Narrow createInRealm:realm withValue:@[@((int)i), randWord(12), @(arc4random() / (double)UINT32_MAX * 100.0), @(i % 2 == 0), [NSDate dateWithTimeIntervalSince1970:1.2e9 + i * 11.0]]]; }];
    NSLog(@"done: %lu rows per class", (unsigned long)rows);
} return 0; }
EOF
clang -fobjc-arc -fmodules -O2 -F "$DD/Realm" -framework Realm -framework Foundation -Wl,-rpath,"$DD/Realm" /tmp/rlmperf/gen.m -o /tmp/rlmperf/gen && /tmp/rlmperf/gen /tmp/rlmperf/perf.realm 200000
```

- [ ] **Step 2: Functional checklist (Debug build, `/tmp/rlmperf/perf.realm`, window maximised)**

Open the file and confirm each item:
- Sidebar: Narrow → Wide → Wide2 → Narrow switch instantly; status label shows "200000 items"; first row selected; column widths fit content.
- Wide: ints/doubles formatted as before; `flag1`/`flag2` drawn checkboxes; `created` dates; `owner` link-coloured `Tiny(...)` text (rows where it is nil show the "nil" placeholder); `tags` shows `Tiny` plus a count pill; `optInt` shows numbers or "nil".
- Selected row: white text, white checkbox/pill; non-selected rows unchanged; window inactive → selection grey, text legible.
- Click `owner` link cell → navigates to `Tiny` with that object selected; Back returns. Click `tags` cell → array view with `#` gutter column counting from 0; drag a row to reorder (drag image visible); context menu "Remove objects from array" works.
- Column resize by dragging a header divider re-lays text immediately; double-click a header divider auto-fits.
- Scroll with trackpad to the bottom and back: smooth, no blank rows, no stale content.
- Search field query (e.g. `a > 1000000000`) shows results; clicking a result row selects it and the inspector updates.
- Dark mode (System Settings or `defaults write com.realm.RealmBrowser NSRequiresAquaSystemAppearance …` is not needed — just toggle appearance): text, placeholders, checkbox and pill colours adapt.
- Popover: right-click a link cell → "Add link to object" → the popover table (also an `RLMInstanceTableViewController`) lists objects and selecting one sets the link.

- [ ] **Step 3: Measure with Instruments**

Launch the **Release** build with the perf realm, maximise the window, then: `xcrun xctrace record --template 'Time Profiler' --attach 'Realm Browser' --time-limit 20s --output /tmp/rlmperf/after.trace` and, while it records, click Wide → Wide2 → Narrow → Wide … about ten times. Open the trace in Instruments (`open /tmp/rlmperf/after.trace`), select the main thread, and confirm:
- No `RLMBasicTableCellView`/`RLMBoolTableCellView`/`NSButton` symbols anywhere; `-[NSTableView makeViewWithIdentifier:owner:]` is negligible.
- `-[RLMDrawnRowView drawRect:]` is the dominant app symbol under `CA::Transaction::commit` and the total per click (from `-[RLMRealmBrowserWindowController addNavigationState:fromViewController:]` start to the following commit) is in the tens of milliseconds — the audit prototype measured 36–50 ms for 1300 visible cells against ≈500 ms before. If a click is still > 100 ms, look for `reloadData`, `_setDefaultKeyViewLoop` cascades into subviews (there must be no subviews), or `sizeWithAttributes:` dominating (`sizeColumnsToFitOnscreenContents` measures up to 50 rows × columns; acceptable).

- [ ] **Step 4: Record results**

Append the measured before/after numbers and the macOS/Xcode versions to `CHANGELOG.md` under the next version heading (one bullet: "Instance table rows now draw their columns directly; switching classes with ~1300 visible cells went from ≈500 ms to ≈40 ms on macOS 26"). Commit:

```bash
git add CHANGELOG.md
git commit -m "Changelog: drawn row view table performance"
```

---

## Self-review notes

- Every behaviour listed in the Design mapping table is implemented: text/placeholder/link/bool/optional-bool/badge/gutter (Task 3 + Task 2), tooltips and inline editing (Task 5), fine-grained updates and navigation reload strategy (Task 4), drag image and accessibility (Task 6), dead-class removal and expansion tooltips (Task 7), measurement (Task 8).
- Names used consistently across tasks: `RLMCellContent` (+ `textContent:showsNilPlaceholder:`, `linkContent:`, `boolContent:`, `badgeContent:count:`, `accessibilityValueString`), `RLMDrawnRowView` (+ `tableView`, `contentDataSource`, `cellTextFont`, `cellTextHeight`), `RLMDrawnRowViewReuseIdentifier`, `RLMDrawnRowViewDataSource` → `rowView:contentForTableColumn:row:`, `RLMTableView` → `redrawAllRows`, `redrawRowsAtIndexes:`.
- Known limitation (intentional, matches today's behaviour): bool checkboxes and optional-bool values are display-only; editing them is not supported (it was not before either — the old controls were disabled).
