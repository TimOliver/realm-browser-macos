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

@import QuartzCore;

#import "RLMTableView.h"
#import "RLMTableColumn.h"
#import "RLMArrayNode.h"
#import "RLMDescriptions.h"

const NSInteger NOT_A_COLUMN = -1;

static void RLMPerformWithoutAnimations(void (^changes)(void))
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.0;
        context.allowsImplicitAnimation = NO;
        changes();
    } completionHandler:nil];
    [CATransaction commit];
}

static NSDictionary<NSAnimatablePropertyKey, id> *RLMDisabledViewAnimations(void)
{
    static NSDictionary<NSAnimatablePropertyKey, id> *animations = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        animations = @{
            @"bounds": [NSNull null],
            @"boundsOrigin": [NSNull null],
            @"boundsSize": [NSNull null],
            @"contents": [NSNull null],
            @"frame": [NSNull null],
            @"frameOrigin": [NSNull null],
            @"frameSize": [NSNull null],
            @"hidden": [NSNull null],
            @"position": [NSNull null],
        };
    });
    return animations;
}

@interface RLMTableHeaderView : NSTableHeaderView
@end

@implementation RLMTableHeaderView

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        self.animations = RLMDisabledViewAnimations();
    }
    return self;
}

- (void)setFrame:(NSRect)frameRect
{
    RLMPerformWithoutAnimations(^{
        [super setFrame:frameRect];
    });
}

- (void)setBounds:(NSRect)boundsRect
{
    RLMPerformWithoutAnimations(^{
        [super setBounds:boundsRect];
    });
}

// The instance table is layer-backed for scrolling performance. When columns are
// re-used for a different class, the header's layer otherwise animates the
// redrawn title positions/contents, which reads as the titles sliding into place.
- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event
{
    return (id<CAAction>)[NSNull null];
}

@end

@interface RLMTableView()<NSMenuDelegate>

- (void)disableColumnAnimationOnScrollView;
- (void)settleColumnGeometry;

@end

@implementation RLMTableView {
    NSTrackingArea *trackingArea;
    RLMTableLocation currentMouseLocation;
    RLMTableLocation previousMouseLocation;
    NSString *currentColumnSignature;
    NSString *currentTypeName;
    BOOL applyingFittedWidths;
    BOOL widthsChanged;
    NSMutableDictionary<NSString *, NSNumber *> *fittedColumnWidths;

    NSMenuItem *clickLockItem;

    NSMenuItem *deleteObjectItem;
    NSMenuItem *copyValueItem;

    NSMenuItem *removeFromArrayItem;
    NSMenuItem *deleteRowItem;
    NSMenuItem *insertIntoArrayItem;
    NSMenuItem *insertLinkInArray;

    NSMenuItem *setLinkToObjectItem;
    NSMenuItem *removeLinkToObjectItem;
    NSMenuItem *removeLinkToArrayItem;
    
    NSMenuItem *openArrayInNewWindowItem;
}

#pragma mark - NSObject Overrides

- (void)awakeFromNib
{
    [super awakeFromNib];

    int options = NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect | NSTrackingMouseEnteredAndExited
    | NSTrackingMouseMoved | NSTrackingCursorUpdate;
    trackingArea = [[NSTrackingArea alloc] initWithRect:[self bounds] options:options owner:self userInfo:nil];
    [self addTrackingArea:trackingArea];

    currentMouseLocation = RLMTableLocationUndefined;
    previousMouseLocation = RLMTableLocationUndefined;

    [self createContextMenuItems];
    self.allowsColumnReordering = NO;
    [self disableColumnAnimationOnScrollView];



    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(columnDidResize:)
                                                 name:NSTableViewColumnDidResizeNotification
                                               object:self];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (trackingArea != nil) {
        [self removeTrackingArea:trackingArea];
    }
}

#pragma mark - Public methods - Accessors

-(id<RLMTableViewDelegate>)realmDelegate
{
    return (id<RLMTableViewDelegate>)self.delegate;
}

-(id<RLMTableViewDataSource>)realmDataSource
{
    return (id<RLMTableViewDataSource>)self.dataSource;
}

#pragma mark - Private Methods - NSObject Overrides

enum MenuTags {
    MENU_CONTEXT_CLICK_LOCK_ICON_TO_EDIT = 99,
    MENU_CONTEXT_DELETE_OBJECTS = 200,
    MENU_CONTEXT_COPY_VALUE = 201,

    MENU_CONTEXT_ARRAY_REMOVE_OBJECTS = 210,
    MENU_CONTEXT_ARRAY_DELETE_OBJECTS = 211,
    MENU_CONTEXT_ARRAY_ADD_NEW = 212,
    MENU_CONTEXT_ARRAY_ADD_EXISTING = 213,
    MENU_CONTEXT_ARRAY_CLEAR = 221,
    MENU_CONTEXT_ARRAY_OPEN = 230,

    MENU_CONTEXT_LINK_SET = 217,
    MENU_CONTEXT_REMOVE_BACKLINKS = 220,
};

-(void)createContextMenuItems
{
    NSMenu *rightClickMenu = [[NSMenu alloc] initWithTitle:@"Contextual Menu"];
    self.menu = rightClickMenu;
    self.menu.delegate = self;
    
    // This single menu item alerts the user that the realm is locked for editing
    clickLockItem = [[NSMenuItem alloc] initWithTitle:@"Click lock icon to edit"
                                               action:nil
                                        keyEquivalent:@""];
    clickLockItem.tag = MENU_CONTEXT_CLICK_LOCK_ICON_TO_EDIT;
    
    // Operations on objects in class tables
    deleteObjectItem = [[NSMenuItem alloc] initWithTitle:@"Delete objects"
                                                  action:@selector(deleteObjectsAction:)
                                           keyEquivalent:@""];
    deleteObjectItem.tag = MENU_CONTEXT_DELETE_OBJECTS;
    
    copyValueItem = [[NSMenuItem alloc] initWithTitle:@"Copy value"
                                                  action:@selector(copyValueAction:)
                                           keyEquivalent:@""];
    copyValueItem.tag = MENU_CONTEXT_COPY_VALUE;

    // Operations on objects in arrays
    removeFromArrayItem = [[NSMenuItem alloc] initWithTitle:@"Remove objects from array"
                                                     action:@selector(removeRowsFromArrayAction:)
                                              keyEquivalent:@""];
    removeFromArrayItem.tag = MENU_CONTEXT_ARRAY_REMOVE_OBJECTS;
    
    deleteRowItem = [[NSMenuItem alloc] initWithTitle:@"Remove objects from array and delete"
                                               action:@selector(deleteRowsFromArrayAction:)
                                        keyEquivalent:@""];
    deleteRowItem.tag = MENU_CONTEXT_ARRAY_DELETE_OBJECTS;
    
    insertIntoArrayItem = [[NSMenuItem alloc] initWithTitle:@"Add new objects to array"
                                                     action:@selector(addRowsToArrayAction:)
                                              keyEquivalent:@""];
    insertIntoArrayItem.tag = MENU_CONTEXT_ARRAY_ADD_NEW;

    insertLinkInArray = [[NSMenuItem alloc] initWithTitle:@"Add existing object to array"
                                                     action:@selector(insertRowsToArrayAction:)
                                              keyEquivalent:@""];
    insertLinkInArray.tag = MENU_CONTEXT_ARRAY_ADD_EXISTING;

    // Operations on links in cells
    setLinkToObjectItem = [[NSMenuItem alloc] initWithTitle:@"Add link to object"
                                                     action:@selector(setObjectLinkAction:)
                                              keyEquivalent:@""];
    setLinkToObjectItem.tag = MENU_CONTEXT_LINK_SET;
    
    removeLinkToObjectItem= [[NSMenuItem alloc] initWithTitle:@"Remove link to object"
                                                       action:@selector(removeObjectLinksAction:)
                                                keyEquivalent:@""];
    removeLinkToObjectItem.tag = MENU_CONTEXT_REMOVE_BACKLINKS;
    
    removeLinkToArrayItem = [[NSMenuItem alloc] initWithTitle:@"Make array empty"
                                                       action:@selector(removeArrayLinksAction:)
                                                keyEquivalent:@""];
    removeLinkToArrayItem.tag = MENU_CONTEXT_ARRAY_CLEAR;
    
    // Open array in new window
    openArrayInNewWindowItem = [[NSMenuItem alloc] initWithTitle:@"Open array in new window"
                                                          action:@selector(openArrayInNewWindowAction:)
                                                   keyEquivalent:@""];
    openArrayInNewWindowItem.tag = MENU_CONTEXT_ARRAY_OPEN;
}

#pragma mark - NSMenu Delegate

// Called on the context menu before displaying
-(void)menuNeedsUpdate:(NSMenu *)menu
{
    [self.menu removeAllItems];
    
    BOOL actualColumn = self.clickedColumn != NOT_A_COLUMN;

    if (actualColumn && [self.realmDelegate containsArrayInRows:self.selectedRowIndexes column:self.clickedColumn]) {
        [self.menu addItem:openArrayInNewWindowItem];
        [self.menu addItem:insertLinkInArray];
    }

    if (self.realmDelegate.displaysArray) {
        [self.menu addItem:insertIntoArrayItem];
        [self.menu addItem:insertLinkInArray];
    }
    
    if (actualColumn && [self.realmDelegate isColumnObjectType:self.clickedColumn]) {
        [self.menu addItem:setLinkToObjectItem];
    }
    
    if (self.selectedRowIndexes.count == 0) {
        return;
    }
    
    // Below, only menu items that make sense with a row selected
    
    if (self.realmDelegate.displaysArray) {
        [self.menu addItem:removeFromArrayItem];
        [self.menu addItem:deleteRowItem];
    }
    else {
        [self.menu addItem:deleteObjectItem];
        [self.menu addItem:copyValueItem];
    }
    
    if (!actualColumn) {
        return;
    }
    
    // Below, only menu items that make sense when clicking in a column
    
    if ([self.realmDelegate containsObjectInRows:self.selectedRowIndexes column:self.clickedColumn]) {
        [self.menu addItem:removeLinkToObjectItem];
    }
    else if ([self.realmDelegate containsArrayInRows:self.selectedRowIndexes column:self.clickedColumn]) {
        [self.menu addItem:removeLinkToArrayItem];
    }
}

#pragma mark - NSResponder Overrides

- (void)cursorUpdate:(NSEvent *)event
{
    [self mouseMoved: event];
    
    // Note: This method is left mostly empty on purpose. It avoids cursor events to be passed on up
    //       the responder chain where it potentially could reach a displayed tool-tip view, which
    //       will undo any modification to the cursor image dome by the application. This "fix" is
    //       in order to circumvent a bug in OS X version prior to 10.10 Yosemite not honouring
    //       the NSTrackingActiveAlways option even when the cursorRect has been disabled.
    //       IMPORTANT: Must NOT be deleted!!!
}

- (void)mouseMoved:(NSEvent *)event
{
    if (!self.delegate) {
        return; // No delegate, no need to track the mouse.
    }
        
    currentMouseLocation = [self currentLocationAtPoint:[event locationInWindow]];

    if (RLMTableLocationEqual(previousMouseLocation, currentMouseLocation)) {
        return;
    }
    else {
        if ([self.delegate respondsToSelector:@selector(mouseDidExitCellAtLocation:)]) {
            [(id<RLMTableViewDelegate>)self.delegate mouseDidExitCellAtLocation:previousMouseLocation];
        }
        
        CGRect cellRect = [self rectOfLocation:previousMouseLocation];
        [self setNeedsDisplayInRect:cellRect];
        
        previousMouseLocation = currentMouseLocation;
        
        if ([self.delegate respondsToSelector:@selector(mouseDidEnterCellAtLocation:)]) {
            [(id<RLMTableViewDelegate>)self.delegate mouseDidEnterCellAtLocation:currentMouseLocation];
        }
    }
    
    CGRect cellRect = [self rectOfLocation:currentMouseLocation];
    [self setNeedsDisplayInRect:cellRect];
}

-(void)rightMouseDown:(NSEvent *)theEvent
{
    RLMTableLocation location = [self currentLocationAtPoint:[theEvent locationInWindow]];
    
    if ([self.delegate respondsToSelector:@selector(rightClickedLocation:)]) {
        [(id<RLMTableViewDelegate>)self.delegate rightClickedLocation:location];
    }
    [super rightMouseDown:theEvent];
}

- (void)mouseExited:(NSEvent *)theEvent
{    
    CGRect cellRect = [self rectOfLocation:currentMouseLocation];
    [self setNeedsDisplayInRect:cellRect];
    
    currentMouseLocation = RLMTableLocationUndefined;
    previousMouseLocation = RLMTableLocationUndefined;
    
    if ([self.delegate respondsToSelector:@selector(mouseDidExitView:)]) {
        [(id<RLMTableViewDelegate>)self.delegate mouseDidExitView:self];
    }
}

-(BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    BOOL nonemptySelection = self.selectedRowIndexes.count > 0;
    BOOL multipleSelection = self.selectedRowIndexes.count > 1;
    BOOL displaysArray = self.realmDelegate.displaysArray;

    NSString *numberModifier = multipleSelection ? @"s" : @"";

    switch (menuItem.tag) {
        case MENU_CONTEXT_CLICK_LOCK_ICON_TO_EDIT: // Retired click-lock hint
            return NO;

        case 100: // Edit -> Delete object
        case MENU_CONTEXT_DELETE_OBJECTS: // Context -> Delete object
            menuItem.title = [NSString stringWithFormat:@"Delete object%@", numberModifier];
            return nonemptySelection && !displaysArray;

        case 101: // Edit -> Add object
            menuItem.title = [NSString stringWithFormat:@"Add new object%@", numberModifier];
            return !displaysArray;

        case 110: // Edit -> Remove object from array
        case MENU_CONTEXT_ARRAY_REMOVE_OBJECTS: // Context -> Remove object from array
            menuItem.title = [NSString stringWithFormat:@"Remove object%@ from array", numberModifier];
            return nonemptySelection && displaysArray;

        case 111: // Edit -> Remove object from array and delete
        case MENU_CONTEXT_ARRAY_DELETE_OBJECTS: // Context -> Remove object from array and delete
            menuItem.title = [NSString stringWithFormat:@"Remove object%@ from array and delete", numberModifier];
            return nonemptySelection && displaysArray;

        case 112: // Edit -> Insert object into array
        case MENU_CONTEXT_ARRAY_ADD_NEW: // Context -> Insert object into array
            menuItem.title = [NSString stringWithFormat:@"Add new object%@ to array", numberModifier];
            return displaysArray;

        case 113: // Edit -> Add existing object to array
        case MENU_CONTEXT_ARRAY_ADD_EXISTING: // Context -> Add existing object to array
            menuItem.title = [NSString stringWithFormat:@"Add existing object%@ to array", numberModifier];
            return displaysArray;

        case MENU_CONTEXT_REMOVE_BACKLINKS: // Context -> Remove links to object
            menuItem.title = [NSString stringWithFormat:@"Remove link%@ to object%@", numberModifier, numberModifier];
            return nonemptySelection;

        case MENU_CONTEXT_ARRAY_CLEAR: // Context -> Remove links to array
            menuItem.title = [NSString stringWithFormat:@"Make array%@ empty", numberModifier];
            return nonemptySelection;

        case MENU_CONTEXT_ARRAY_OPEN: // Context -> Open array in new window
            menuItem.title = @"Open array in new window";
            return YES;

        default:
            return YES;
    }
}

#pragma mark - First Responder User Actions

// Delete selected objects
- (IBAction)deleteObjectsAction:(id)sender
{
    if (!self.realmDelegate.displaysArray) {
        [self.realmDelegate deleteObjects:self.selectedRowIndexes];
    }
}

// Copies the value from the cell that was right-clicked
- (IBAction)copyValueAction:(id)sender
{
    [self.realmDelegate copyValueFromRow:self.clickedRow column:self.clickedColumn];
}

// Add objects of the current type, according to number of selected rows
- (IBAction)addObjectsAction:(id)sender
{
    if (!self.realmDelegate.displaysArray) {
        [self.realmDelegate addNewObjects:self.selectedRowIndexes];
    }
}

// Remove selected objects from array, keeping the objects
- (IBAction)removeRowsFromArrayAction:(id)sender
{
    if (self.realmDelegate.displaysArray) {
        [self.realmDelegate removeRows:self.selectedRowIndexes];
    }
}

// Remove selected objects from array and delete the objects
- (IBAction)deleteRowsFromArrayAction:(id)sender
{
    if (self.realmDelegate.displaysArray) {
        [self.realmDelegate deleteRows:self.selectedRowIndexes];
    }
}

// Create and insert objects at the selected rows
- (IBAction)addRowsToArrayAction:(id)sender
{
    if (self.realmDelegate.displaysArray) {
        NSInteger index = self.selectedRowIndexes.count > 0 ? self.selectedRowIndexes.lastIndex + 1 : self.numberOfRows;

        [self.realmDelegate addNewRows:[NSIndexSet indexSetWithIndex:index]];
    }
}

// Insert link into array
- (IBAction)insertRowsToArrayAction:(id)sender
{
    if (self.realmDelegate.displaysArray) {
        NSInteger index = self.selectedRowIndexes.count > 0 ? self.selectedRowIndexes.lastIndex + 1 : self.numberOfRows;

        [self.realmDelegate insertLinks:[NSIndexSet indexSetWithIndex:index] column:self.clickedColumn];
    }
}

// Set object links in the clicked column to [NSNull null] at the selected rows
- (IBAction)setObjectLinkAction:(id)sender
{
    [self.realmDelegate setObjectLinkAtRows:self.selectedRowIndexes column:self.clickedColumn];
}

// Set object links in the clicked column to [NSNull null] at the selected rows
- (IBAction)removeObjectLinksAction:(id)sender
{
    [self.realmDelegate removeObjectLinksAtRows:self.selectedRowIndexes column:self.clickedColumn];
}

// Make array links in the clicked column, at selected rows, empty
- (IBAction)removeArrayLinksAction:(id)sender
{
    [self.realmDelegate removeArrayLinksAtRows:self.selectedRowIndexes column:self.clickedColumn];
}

// Opens the array in the current cell in a new window
- (IBAction)openArrayInNewWindowAction:(id)sender
{
    [self.realmDelegate openArrayInNewWindowAtRow:self.clickedRow column:self.clickedColumn];
}

#pragma mark - NSView Overrides

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    
    if (trackingArea != nil) {
        [self removeTrackingArea:trackingArea];
    }
    int opts = NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect | NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved;
    trackingArea = [[NSTrackingArea alloc] initWithRect:[self bounds] options:opts owner:self userInfo:nil];
    [self addTrackingArea:trackingArea];
}

#pragma mark - Public Methods

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

- (void)scrollToRow:(NSInteger)rowIndex
{
    NSRect rowRect = [self rectOfRow:rowIndex];
    NSPoint scrollOrigin = rowRect.origin;
    NSClipView *clipView = (NSClipView *)[self superview];
    scrollOrigin.y += MAX(0, round((NSHeight(rowRect) - NSHeight(clipView.frame))*0.5f));
    NSScrollView *scrollView = (NSScrollView *)[clipView superview];
    if ([scrollView respondsToSelector:@selector(flashScrollers)]){
        [scrollView flashScrollers];
    }
    [[clipView animator] setBoundsOrigin:scrollOrigin];
}

- (void)setupColumnsWithType:(RLMTypeNode *)typeNode
{
    BOOL isArray = [typeNode isMemberOfClass:[RLMArrayNode class]];
    NSArray *newPropertyColumns = typeNode.propertyColumns;
    currentTypeName = typeNode.name;

    // Rebuilding NSTableView columns is one of the most expensive parts of a
    // navigation, and most navigations (link clicks, queries, back/forward within
    // one class) keep the exact same schema. When nothing about the columns would
    // change, keep them — and the table's cell reuse pool — and just re-point them
    // at the new node's properties.
    NSMutableString *signature = [NSMutableString stringWithString:isArray ? @"#|" : @""];
    for (RLMClassProperty *propertyColumn in newPropertyColumns) {
        [signature appendFormat:@"%@:%ld:%d:%d|", propertyColumn.name, (long)propertyColumn.type,
                                propertyColumn.property.optional, propertyColumn.property.array];
    }

    if ([signature isEqualToString:currentColumnSignature]) {
        NSUInteger firstPropertyColumn = isArray ? 1 : 0;
        RLMPerformWithoutAnimations(^{
            for (NSUInteger index = 0; index < newPropertyColumns.count; index++) {
                RLMTableColumn *tableColumn = (RLMTableColumn *)self.tableColumns[firstPropertyColumn + index];
                tableColumn.classProperty = newPropertyColumns[index];
                tableColumn.cachedHeaderToolTip = nil; // The statistics reflect the new node's data
            }
            // Not reloadData: that purges the row reuse pool, and the rows would all be
            // rebuilt. The row count is updated and every visible row redraws its content.
            [self noteNumberOfRowsChanged];
            [self redrawAllRows];
        });
        return;
    }
    currentColumnSignature = signature;

    RLMPerformWithoutAnimations(^{
        // Column mutations synchronously write table-state autosave entries — still
        // keyed to the *outgoing* class's autosave name at this point — so suspend
        // autosaving while rebuilding. The window controller re-enables it with the
        // new class's name once the columns are in place.
        self.autosaveTableColumns = NO;
        self.autosaveName = nil;

        // Columns are pooled: the pool grows to the widest schema seen and columns
        // are reconfigured in place — never removed — with the surplus hidden. This
        // keeps the table's cell reuse queues alive across class switches, so most
        // of row population becomes re-binding existing views instead of creating
        // them.
        NSUInteger neededColumns = newPropertyColumns.count + (isArray ? 1 : 0);

        // Deliberately not inside beginUpdates/endUpdates: that is NSTableView's animated
        // batch-update API, so the pooled columns animate to the positions the new class
        // gives them instead of simply being there when the table redraws.
        while ((NSUInteger)self.numberOfColumns < neededColumns) {
            RLMTableColumn *column = [[RLMTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"pool.%ld", (long)self.numberOfColumns]];
            column.minWidth = 26.0;
            [self addTableColumn:column];
        }

        NSUInteger columnIndex = 0;

        // If array, the first column shows the element index
        if (isArray) {
            RLMTableColumn *tableColumn = (RLMTableColumn *)self.tableColumns[columnIndex++];
            tableColumn.hidden = NO;
            tableColumn.identifier = @"#";
            tableColumn.propertyType = RLMPropertyTypeInt;
            tableColumn.classProperty = nil;
            tableColumn.title = @"#";
            tableColumn.headerToolTip = @"Order of object within array";
            [self restoreFittedWidthForColumn:tableColumn];
        }

        for (RLMClassProperty *propertyColumn in newPropertyColumns) {
            RLMTableColumn *tableColumn = (RLMTableColumn *)self.tableColumns[columnIndex++];
            tableColumn.hidden = NO;
            tableColumn.identifier = propertyColumn.name;
            tableColumn.propertyType = propertyColumn.type;
            // The statistics tooltip requires full-table aggregate queries, so it is
            // computed lazily on first hover (see stringForToolTip:) rather than here.
            tableColumn.classProperty = propertyColumn;
            tableColumn.title = propertyColumn.name;
            tableColumn.headerToolTip = nil;

            [self restoreFittedWidthForColumn:tableColumn];
        }

        // Park the rest of the pool out of sight, under identifiers that cannot
        // collide with a property name in the column-state autosave archive.
        for (; columnIndex < (NSUInteger)self.numberOfColumns; columnIndex++) {
            RLMTableColumn *tableColumn = (RLMTableColumn *)self.tableColumns[columnIndex];
            tableColumn.hidden = YES;
            tableColumn.identifier = [NSString stringWithFormat:@"pool.unused.%lu", (unsigned long)columnIndex];
            tableColumn.classProperty = nil;
        }

        // Not reloadData: that purges the row reuse pool, and the rows would all be
        // rebuilt. The row count is updated and every visible row redraws its content.
        [self noteNumberOfRowsChanged];
        [self settleColumnGeometry];
        [self redrawAllRows];

        [self updateHeaderToolTipRects];
    });
}

#pragma mark - Private Methods - Header tooltips

- (void)updateHeaderToolTipRects
{
    NSTableHeaderView *headerView = self.headerView;
    [headerView removeAllToolTips];
    for (NSInteger index = 0; index < self.numberOfColumns; index++) {
        [headerView addToolTipRect:[headerView headerRectOfColumn:index] owner:self userData:NULL];
    }
}

- (void)columnDidResize:(NSNotification *)notification
{
    // While auto-fitting, the same work is done once at the end of the pass.
    if (applyingFittedWidths) {
        return;
    }
    [self updateHeaderToolTipRects];
    [self redrawAllRows];
}

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data
{
    NSInteger columnIndex = [self.headerView columnAtPoint:point];
    if (columnIndex < 0 || columnIndex >= self.numberOfColumns) {
        return nil;
    }

    NSTableColumn *column = self.tableColumns[columnIndex];
    if (![column isKindOfClass:[RLMTableColumn class]]) {
        return column.headerToolTip;
    }

    RLMTableColumn *realmColumn = (RLMTableColumn *)column;
    if (realmColumn.classProperty && realmColumn.cachedHeaderToolTip == nil) {
        realmColumn.cachedHeaderToolTip = [self.realmDataSource headerToolTipForColumn:realmColumn.classProperty] ?: @"";
    }
    return realmColumn.cachedHeaderToolTip.length > 0 ? realmColumn.cachedHeaderToolTip : column.headerToolTip;
}

#pragma mark - Private Methods - Table Columns

// A single long value must not consume the whole window when deriving a
// column's natural width from its content.
static const CGFloat kMaxNaturalColumnWidth = 400.0;
static const NSInteger kMaxRowsToMeasureForFit = 20;

- (void)sizeColumnsToFitOnscreenContents
{
    // Rows currently on screen; before the first layout the visible rect can be
    // empty, so fall back to the first screenful.
    NSRange rowRange = [self rowsInRect:self.visibleRect];
    if (rowRange.length == 0) {
        rowRange = NSMakeRange(0, (NSUInteger)MIN((NSInteger)kMaxRowsToMeasureForFit, self.numberOfRows));
    }
    // Measuring a cell costs roughly as much as drawing a whole row, so the number
    // measured per column is capped: a maximised window would otherwise measure a
    // full screenful of rows for every column on every navigation.
    rowRange.length = MIN(rowRange.length, (NSUInteger)kMaxRowsToMeasureForFit);

    // Column width changes synchronously write the table's autosave state; the fit
    // would otherwise pay for that once per column.
    BOOL wasAutosavingColumns = self.autosaveTableColumns;
    RLMPerformWithoutAnimations(^{
        self.autosaveTableColumns = NO;
        applyingFittedWidths = YES;
        widthsChanged = NO;
        // Deliberately not inside beginUpdates/endUpdates: that is NSTableView's animated
        // batch-update API, and it animates the column geometry -- the header titles slide
        // into their new positions. Assigning the widths plainly costs a little more, and
        // is the reason the widths are cached per class so most navigations assign nothing.

        // Each column gets exactly its natural width — the header title plus the
        // widest cell among the measured rows. No fill-out: a column of nils stays
        // as narrow as its title, regardless of the window size.
        for (RLMTableColumn *column in self.tableColumns) {
            if (column.hidden) {
                continue;
            }

            // Widths are fitted once per class: revisiting one (or coming back from a
            // link, an array or a search) reuses what was measured the first time.
            NSString *cacheKey = [self fittedWidthKeyForColumn:column];
            NSNumber *fittedWidth = (cacheKey != nil) ? fittedColumnWidths[cacheKey] : nil;
            if (fittedWidth != nil) {
                [self applyFittedWidth:fittedWidth.doubleValue toColumn:column];
                continue;
            }

            CGFloat width = MIN([column widthThatFitsRows:rowRange], kMaxNaturalColumnWidth);
            [self applyFittedWidth:width toColumn:column];
            [self setFittedWidth:width forColumn:column];
        }

        applyingFittedWidths = NO;
        self.autosaveTableColumns = wasAutosavingColumns;
        if (widthsChanged) {
            [self settleColumnGeometry];

            // Done once rather than per column: -columnDidResize: rebuilds every header
            // tooltip rect and repaints every row, and a wide class would otherwise pay
            // for that once per column.
            [self updateHeaderToolTipRects];
            [self redrawAllRows];
        }
    });
}

// Assigning a column width is expensive — AppKit re-tiles every column after it and
// writes the table's autosave state — so widths that already match are left alone.
- (void)applyFittedWidth:(CGFloat)width toColumn:(RLMTableColumn *)column
{
    if (column.width == width) {
        return;
    }
    column.width = width;
    widthsChanged = YES;
}

// Restores the width already fitted for this class, if there is one. Columns without a
// remembered width are left alone here and sized once by the auto-fit pass that follows,
// so no column is ever given a placeholder width and resized afterwards.
- (void)restoreFittedWidthForColumn:(RLMTableColumn *)column
{
    NSString *key = [self fittedWidthKeyForColumn:column];
    NSNumber *fittedWidth = (key != nil) ? fittedColumnWidths[key] : nil;
    if (fittedWidth != nil) {
        column.width = fittedWidth.doubleValue;
    }
}

// nil until the columns have been set up for a type, which is what the widths belong to.
- (NSString *)fittedWidthKeyForColumn:(RLMTableColumn *)column
{
    if (currentTypeName == nil || column.identifier == nil) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@|%@", currentTypeName, column.identifier];
}

- (void)setFittedWidth:(CGFloat)width forColumn:(RLMTableColumn *)column
{
    NSString *key = [self fittedWidthKeyForColumn:column];
    if (key == nil) {
        return;
    }
    if (fittedColumnWidths == nil) {
        fittedColumnWidths = [NSMutableDictionary dictionary];
    }
    fittedColumnWidths[key] = @(width);
}

- (void)disableColumnAnimationOnScrollView
{
    NSDictionary<NSAnimatablePropertyKey, id> *disabledAnimations = RLMDisabledViewAnimations();
    self.animations = disabledAnimations;
    self.headerView.animations = disabledAnimations;
    self.enclosingScrollView.animations = disabledAnimations;
    self.enclosingScrollView.contentView.animations = disabledAnimations;
}

- (void)settleColumnGeometry
{
    [self disableColumnAnimationOnScrollView];

    // The columns are in their final hidden/title/width state now, so make AppKit
    // settle the table, clip view and header before the current transaction commits.
    // Otherwise the layer-backed header can briefly present the new titles using
    // stale column frames, which reads as the titles sliding around on appear.
    [self tile];
    [self.enclosingScrollView tile];
    [self layoutSubtreeIfNeeded];
    [self.headerView layoutSubtreeIfNeeded];
    [self.headerView setNeedsDisplay:YES];
    [self.headerView displayIfNeeded];
}

#pragma mark - Private Methods - Cell geometry

- (RLMTableLocation)currentLocationAtPoint:(NSPoint)point
{
    NSPoint localPointInTable = [self convertPoint:point fromView:nil];
    
    NSInteger row = [self rowAtPoint:localPointInTable];
    NSInteger column = [self columnAtPoint:localPointInTable];
    
    NSPoint localPointInHeader = [self.headerView convertPoint:point fromView:nil];
    if (NSPointInRect(localPointInHeader, self.headerView.bounds)) {
        row = -2;
        column = [self columnAtPoint:localPointInHeader];
    }
    
    return RLMTableLocationMake(row, column);
}

- (CGRect)rectOfLocation:(RLMTableLocation)location
{
    CGRect rowRect = [self rectOfRow:location.row];
    CGRect columnRect = [self rectOfColumn:location.column];
    
    return CGRectIntersection(rowRect, columnRect);
}

@end
