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

#import "RLMInstanceTableViewController.h"
@import Foundation;
@import Realm.Dynamic;

#import "RLMRealmBrowserWindowController.h"
#import "RLMObjectLinkSelectionViewController.h"
#import "RLMArrayNavigationState.h"
#import "RLMQueryNavigationState.h"
#import "RLMArrayNode.h"
#import "RLMResultsNode.h"
#import "RLMRealmNode.h"

#import "RLMDrawnRowView.h"
#import "RLMCellContent.h"

#import "RLMTableColumn.h"

#import "NSColor+ByteSizeFactory.h"

#import "RLMDescriptions.h"

NSString * const kRLMObjectType = @"RLMObjectType";
static const NSInteger NOT_A_COLUMN = -1;
static const NSInteger NOT_A_ROW = -1;

typedef NS_ENUM(int32_t, RLMUpdateType) {
    RLMUpdateTypeRealm,
    RLMUpdateTypeTableView
};

@interface RLMInstanceTableViewController () <NSTextFieldDelegate>

@property (nonatomic, weak) IBOutlet NSTextField *statusLabel;

// Shared overlay editor for inline edits (the drawn-text cells host no fields).
@property (nonatomic, strong) NSTextField *inlineEditorField;
@property (nonatomic) BOOL inlineEditingActive;
@property (nonatomic) BOOL inlineEditingCancelled;

@end

@implementation RLMInstanceTableViewController {
    BOOL awake;
    BOOL linkCursorDisplaying;
    NSDateFormatter *dateFormatter;
    NSNumberFormatter *numberFormatter;
    RLMDescriptions *realmDescriptions;
    RLMNotificationToken *displayedCollectionToken;
    NSInteger pendingScrollRow;
    NSInteger inlineEditingRow;
    NSInteger inlineEditingColumn;
}

- (void)dealloc
{
    [displayedCollectionToken invalidate];
}

- (instancetype)init
{
    return [super initWithNibName:NSStringFromClass(self.class) bundle:nil];
}

#pragma mark - NSObject Overrides

- (void)awakeFromNib
{
    [super awakeFromNib];

    if (awake) {
        return;
    }
    
    [self.tableView setTarget:self];
    [self.tableView setAction:@selector(userClicked:)];
    [self.tableView setDoubleAction:@selector(userDoubleClicked:)];

    dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateStyle = NSDateFormatterMediumStyle;
    dateFormatter.timeStyle = NSDateFormatterShortStyle;
    
    numberFormatter = [[NSNumberFormatter alloc] init];
    numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;
    
    linkCursorDisplaying = NO;
    pendingScrollRow = NOT_A_ROW;
    inlineEditingRow = NOT_A_ROW;
    inlineEditingColumn = NOT_A_COLUMN;

    realmDescriptions = [[RLMDescriptions alloc] init];
    
    [self.tableView registerForDraggedTypes:@[kRLMObjectType]];
    [self.tableView setDraggingSourceOperationMask:NSDragOperationEvery forLocal:YES];

    awake = YES;

    [self updateStatusLabel];
}

- (void)reloadData {
    // A reload rebinds every cell, so an in-flight inline edit can't survive it.
    [self discardInlineEditing];
    [self.tableView reloadData];
    [self updateStatusLabel];
}

- (void)updateStatusLabel {
    if (!self.statusLabel) {
        return;
    }
    NSUInteger count = (NSUInteger)[self numberOfRowsInTableView:self.tableView];
    NSString *word = (count == 1) ? @"item" : @"items";
    self.statusLabel.stringValue = [NSString stringWithFormat:@"%lu %@", (unsigned long)count, word];
}

#pragma mark - Public methods - Accessors

- (RLMTableView *)realmTableView
{
    return (RLMTableView *)self.tableView;
}

#pragma mark - RLMViewController Overrides

- (void)performUpdateUsingState:(RLMNavigationState *)newState oldState:(RLMNavigationState *)oldState
{
    [super performUpdateUsingState:newState oldState:oldState];

    [self discardInlineEditing];
    
    RLMRealm *realm = self.parentWindowController.document.presentedRealm.realm;
    NSInteger selectionIndex = NSNotFound;
    
    if ([newState isMemberOfClass:[RLMNavigationState class]]) {
        self.displayedType = newState.selectedType;

        if (newState.selectedInstanceIndex != NSNotFound) {
            selectionIndex = newState.selectedInstanceIndex;
        } else if (self.displayedType.instanceCount > 0) {
            selectionIndex = 0;
        }
    }
    else if ([newState isMemberOfClass:[RLMArrayNavigationState class]]) {
        RLMArrayNavigationState *arrayState = (RLMArrayNavigationState *)newState;
        
        RLMClassNode *referringType = (RLMClassNode *)arrayState.selectedType;
        RLMObject *referingInstance = [referringType instanceAtIndex:arrayState.selectedInstanceIndex];
        RLMArrayNode *arrayNode = [[RLMArrayNode alloc] initWithReferringProperty:arrayState.property
                                                                         onObject:referingInstance
                                                                            realm:realm];
        self.displayedType = arrayNode;
        selectionIndex = arrayState.arrayIndex;
    }
    else if ([newState isMemberOfClass:[RLMQueryNavigationState class]]) {
        RLMQueryNavigationState *queryState = (RLMQueryNavigationState *)newState;
        
        RLMResultsNode *resultsNode = [[RLMResultsNode alloc] initWithQuery:queryState.searchText
                                                                     result:queryState.results
                                                                  andParent:queryState.selectedType];
        self.displayedType = resultsNode;
        selectionIndex = 0;
    }

    NSString *autosaveName = [NSString stringWithFormat:@"%lu:%@", realm.hash, self.displayedType.name];
    [self.realmTableView setupColumnsWithType:self.displayedType autosaveName:autosaveName];

    // Scrolling a selection into view can force NSTableView to lay out immediately.
    // Do it only after the pooled columns have their final fitted widths, otherwise
    // Sequoia briefly presents the outgoing widths before the auto-fit realigns them.
    if (selectionIndex != NSNotFound) {
        [self setSelectionIndex:selectionIndex];
    }

    [self observeDisplayedCollection];

    [self updateStatusLabel];
}

#pragma mark - Fine-grained change tracking

- (void)observeDisplayedCollection
{
    [displayedCollectionToken invalidate];
    displayedCollectionToken = nil;

    id<RLMCollection> collection = [self.displayedType observableCollection];
    if (collection == nil) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    displayedCollectionToken = [collection addNotificationBlock:^(id<RLMCollection> results, RLMCollectionChange *change, NSError *error) {
        [weakSelf displayedCollectionDidChange:change error:error];
    }];
}

- (void)displayedCollectionDidChange:(RLMCollectionChange *)change error:(NSError *)error
{
    // The initial (change == nil) notification arrives right after subscribing;
    // navigation has already displayed that state. Invalidation of the displayed
    // node is handled by the window controller's realm-level notification, which
    // fires synchronously at commit — before this block can run.
    if (error != nil || change == nil) {
        return;
    }

    NSIndexSet *deletions = [self indexSetFromIndexes:change.deletions];
    NSIndexSet *insertions = [self indexSetFromIndexes:change.insertions];
    NSIndexSet *modifications = [self indexSetFromIndexes:change.modifications];

    NSUInteger totalChanges = deletions.count + insertions.count + modifications.count;
    if (totalChanges > 0) {
        [self discardInlineEditing];

        NSTableView *tableView = self.tableView;
        if (totalChanges > 200) {
            // Row-level bookkeeping costs more than a plain reload at this scale.
            [self reloadData];
        }
        else {
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
        }

        // Keep the inspector in sync when the selected row's object changed.
        NSInteger selectedRow = self.tableView.selectedRow;
        if (selectedRow != NOT_A_ROW && [modifications containsIndex:(NSUInteger)selectedRow]) {
            [self.parentWindowController inspectObject:[self.displayedType instanceAtIndex:selectedRow]];
        }
    }

    // Scrolling to a freshly inserted row has to wait until the row exists.
    if (pendingScrollRow != NOT_A_ROW) {
        NSInteger row = pendingScrollRow;
        pendingScrollRow = NOT_A_ROW;
        if (row < self.tableView.numberOfRows) {
            [self.realmTableView scrollToRow:row];
        }
    }
}

- (NSIndexSet *)indexSetFromIndexes:(NSArray<NSNumber *> *)indexes
{
    NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
    for (NSNumber *index in indexes) {
        [indexSet addIndex:index.unsignedIntegerValue];
    }
    return indexSet;
}

#pragma mark - NSTableView Data Source

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    if (tableView != self.tableView) {
        return 0;
    }

    return self.displayedType.instanceCount;
}

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

- (id<NSPasteboardWriting>)tableView:(NSTableView *)aTableView pasteboardWriterForRow:(NSInteger)row
{
    if (!self.displaysArray) {
        return nil;
    }

    NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
    [item setString:[@(row) stringValue] forType:kRLMObjectType];
    return item;
}

- (NSDragOperation)tableView:(NSTableView *)aTableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{
    if (operation == NSTableViewDropAbove) {
        return NSDragOperationMove;
    }
    
    return NSDragOperationNone;
}

-(void)tableView:(NSTableView *)tableView draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint forRowIndexes:(NSIndexSet *)rowIndexes {
}

- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)destination dropOperation:(NSTableViewDropOperation)operation
{
    if (!self.displaysArray) {
        return NO;
    }

    NSMutableIndexSet *rowIndexes = [NSMutableIndexSet indexSet];
    for (NSPasteboardItem *item in info.draggingPasteboard.pasteboardItems) {
        NSString *rowString = [item stringForType:kRLMObjectType];
        if (rowString) {
            [rowIndexes addIndex:(NSUInteger)rowString.integerValue];
        }
    }
    if (rowIndexes.count == 0) {
        return NO;
    }

    [self moveRowsInRealmFrom:rowIndexes to:destination];
    return YES;
}

#pragma mark - RLMTableView Data Source

-(NSString *)headerToolTipForColumn:(RLMClassProperty *)propertyColumn
{
    numberFormatter.maximumFractionDigits = 3;

    if (propertyColumn.property.array) {
        return nil;
    }

    // For certain types we want to add some statistics
    RLMPropertyType type = propertyColumn.property.type;
    NSString *propertyName = propertyColumn.property.name;
    
    if (![self.displayedType isKindOfClass:[RLMClassNode class]]) {
        return nil;
    }
    
    RLMResults *results = ((RLMClassNode *)self.displayedType).allObjects;
    switch (type) {
        case RLMPropertyTypeInt:
        case RLMPropertyTypeFloat:
        case RLMPropertyTypeDouble: {
            numberFormatter.minimumFractionDigits = (type == RLMPropertyTypeInt) ? 0 : 3;
            NSString *min = [numberFormatter stringFromNumber:[results minOfProperty:propertyName]];
            NSString *avg = [numberFormatter stringFromNumber:[results averageOfProperty:propertyName]];
            NSString *max = [numberFormatter stringFromNumber:[results maxOfProperty:propertyName]];
            NSString *sum = [numberFormatter stringFromNumber:[results sumOfProperty:propertyName]];
            
            return [NSString stringWithFormat:@"Minimum: %@\nAverage: %@\nMaximum: %@\nSum: %@", min, avg, max, sum];
        }
        case RLMPropertyTypeDate: {
            NSString *min = [dateFormatter stringFromDate:[results minOfProperty:propertyName]];
            NSString *max = [dateFormatter stringFromDate:[results maxOfProperty:propertyName]];
            
            return [NSString stringWithFormat:@"Earliest: %@\nLatest: %@", min, max];
        }
        case RLMPropertyTypeBool: {
            NSUInteger count = results.count;
            if (count == 0) return nil;

            // we have to query for both, as there might also be NULL values.
            NSUInteger trueCount  = [results objectsWhere:@"%K == YES", propertyName].count;
            NSUInteger falseCount = [results objectsWhere:@"%K == NO",  propertyName].count;
            float percentTrue  = trueCount * 100.0 / count;
            float percentFalse = falseCount * 100.0 / count;

            return [NSString stringWithFormat:@"True: %lu (%.1f%%)\nFalse: %lu (%.1f%%)",
                    (unsigned long)trueCount, percentTrue, (unsigned long)falseCount, percentFalse];
        }
        default:
            return nil;
    }
}

-(NSString *)displayedStringForColumn:(RLMClassProperty *)propertyColumn row:(NSInteger)rowIndex
{
    RLMObject *instance = [self.displayedType instanceAtIndex:rowIndex];
    id propertyValue = instance[propertyColumn.name];
    if (propertyValue == NSNull.null) {
        propertyValue = nil;
    }
    return [realmDescriptions printablePropertyValue:propertyValue ofType:propertyColumn.property];
}

#pragma mark - NSTableView Delegate

-(CGFloat)tableView:(NSTableView *)tableView sizeToFitWidthOfColumn:(NSInteger)column
{
    RLMTableColumn *tableColumn = (RLMTableColumn *)self.realmTableView.tableColumns[column];
    
    return [tableColumn sizeThatFitsWithLimit:NO];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    if (self.tableView == notification.object) {
        NSInteger selectedIndex = self.tableView.selectedRow;
        [self.parentWindowController.currentState updateSelectionToIndex:selectedIndex];

        RLMObject *selectedInstance = nil;
        if (selectedIndex >= 0 && selectedIndex < (NSInteger)self.displayedType.instanceCount) {
            selectedInstance = [self.displayedType instanceAtIndex:selectedIndex];
        }
        [self.parentWindowController inspectObject:selectedInstance];

        if (self.didSelectedBlock != nil) {
            self.didSelectedBlock(selectedInstance);
        }
    }
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
    // No cell views - RLMDrawnRowView draws every column (see rowView:contentForTableColumn:row:).
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

#pragma mark - RLMTableView Delegate

// Asking the delegate about the state
- (BOOL)displaysArray
{
    return ([self.displayedType isMemberOfClass:[RLMArrayNode class]]);
}

- (BOOL)isColumnObjectType:(NSInteger)column;
{
    NSAssert(column != NOT_A_COLUMN, @"This method can only be used with an actual column index");
    RLMProperty *prop = [self propertyForColumn:column];
    return prop.type == RLMPropertyTypeObject && !prop.array;
}

// Asking the delegate about the contents
- (BOOL)containsObjectInRows:(NSIndexSet *)rowIndexes column:(NSInteger)column;
{
    if (![self isColumnObjectType:column]) {
        return NO;
    }

    NSInteger propertyIndex = [self propertyIndexForColumn:column];
    return [self cellsAreNonEmptyInRows:rowIndexes propertyColumn:propertyIndex];
}

- (BOOL)containsArrayInRows:(NSIndexSet *)rowIndexes column:(NSInteger)column;
{
    NSAssert(column != NOT_A_COLUMN, @"This method can only be used with an actual column index");

    NSInteger propertyIndex = [self propertyIndexForColumn:column];
    
    if (![self propertyForColumn:column].array) {
        return NO;
    }
    
    return [self cellsAreNonEmptyInRows:rowIndexes propertyColumn:propertyIndex];
}

// RLMObject operations (when showing class table)
- (void)deleteObjects:(NSIndexSet *)rowIndexes
{
    // The realm change notification reloads all windows; an explicit reload here
    // would do the full pass a second time.
    [self deleteObjectsInRealmAtIndexes:rowIndexes];
}

- (void)copyValueFromRow:(NSInteger)row column:(NSInteger)column {
    NSInteger propertyIndex = [self propertyIndexForColumn:column];
    RLMClassProperty *classProperty = self.displayedType.propertyColumns[propertyIndex];
    RLMObject *selectedInstance = [self.displayedType instanceAtIndex:row];
    id propertyValue = selectedInstance[classProperty.name];
    NSString *string = [realmDescriptions printablePropertyValue:propertyValue ofType:classProperty.property];

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard writeObjects:@[ string ]];
}

- (void)addNewObjects:(NSIndexSet *)rowIndexes
{
    RLMRealm *realm = self.parentWindowController.document.presentedRealm.realm;
    NSUInteger objectCount = MAX(rowIndexes.count, 1);

    RLMObject *newObject;
    
    [realm beginWriteTransaction];
    for (NSUInteger i = 0; i < objectCount; i++) {
        newObject = [self.class createObjectInRealm:realm withSchema:self.displayedType.schema];
    }
    [realm commitWriteTransaction];
    // The change notification has reloaded all windows by this point.

    if (newObject && [self.displayedType isKindOfClass:RLMClassNode.class]) {
        RLMClassNode *classNode = (RLMClassNode *)self.displayedType;
        // The collection notification that inserts the row arrives on the next
        // runloop pass, so the scroll has to wait for it.
        pendingScrollRow = (NSInteger)[classNode indexOfInstance:newObject];
    }
}

// RLMArray operations
- (void)removeRows:(NSIndexSet *)rowIndexes
{
    [self removeRowsInRealmAt:rowIndexes];
}

- (void)deleteRows:(NSIndexSet *)rowIndexes
{
    [self deleteObjectsInRealmAtIndexes:rowIndexes];
}

- (void)addNewRows:(NSIndexSet *)rowIndexes
{
    [self insertNewRowsInRealmAt:rowIndexes];
}

- (void)presentListPopoverIn:(CGRect)rect nodeType:(RLMTypeNode *)node transaction:(void (^)(RLMObject *))block
{
    RLMObjectLinkSelectionViewController *popoverContent = [RLMObjectLinkSelectionViewController loadInstance];
    NSPopover *popover = [[NSPopover alloc] init];
    popover.contentViewController = popoverContent;
    popover.behavior = NSPopoverBehaviorTransient;

    popoverContent.displayedType = node;

    __weak typeof(self) weakSelf = self;
    __weak typeof(popover) weakPopover = popover;

    popoverContent.didSelectedBlock = ^(RLMObject *object) {
        RLMRealm *realm = weakSelf.parentWindowController.document.presentedRealm.realm;
        [realm beginWriteTransaction];

        block(object);

        [realm commitWriteTransaction];
        [weakPopover close];
    };

    [popover showRelativeToRect:rect ofView:self.tableView preferredEdge:NSMaxYEdge];
}

- (void)insertLinks:(NSIndexSet *)rowIndexes column:(NSInteger)columnIndex
{
    NSArray *topLevelClasses = self.parentWindowController.document.presentedRealm.topLevelClasses;
    NSString *containedClassName = [(RLMArrayNode *)self.displayedType objectClassName];

    RLMTypeNode *node = nil;
    for (RLMClassNode *classNode in topLevelClasses) {
        if ([classNode.name isEqualToString:containedClassName]) {
            node = classNode;
        }
    }
    if (node == nil) return;

    NSRect cellRect = [self.tableView frameOfCellAtColumn:columnIndex row:rowIndexes.firstIndex];

    __weak typeof(self) weakSelf = self;
    [self presentListPopoverIn:cellRect nodeType:node transaction: ^(RLMObject *object) {
        [(RLMArrayNode *)weakSelf.displayedType insertInstance:object atIndex:rowIndexes.firstIndex];
    }];
}

// Operations on links in cells

- (void)setObjectLinkAtRows:(NSIndexSet *)rowIndexes column:(NSInteger)columnIndex {
    NSArray *topLevelClasses = self.parentWindowController.document.presentedRealm.topLevelClasses;
    
    RLMObject *selectedInstance = [self.displayedType instanceAtIndex:rowIndexes.firstIndex];
    NSInteger propertyIndex = [self propertyIndexForColumn:columnIndex];
    
    RLMRealm *realm = self.parentWindowController.document.presentedRealm.realm;
    RLMObjectSchema *objectSchema = [realm.schema schemaForClassName:self.displayedType.name];
    RLMProperty *property = objectSchema.properties[propertyIndex];

    RLMTypeNode *node = nil;
    for (RLMClassNode *classNode in topLevelClasses) {
        if ([classNode.name isEqualToString:property.objectClassName]) {
            node = classNode;
        }
    }
    if (node == nil) return;

    NSRect cellRect = [self.tableView frameOfCellAtColumn:columnIndex row:rowIndexes.firstIndex];

    __weak typeof(self) weakSelf = self;
    [self presentListPopoverIn:cellRect nodeType:node transaction:^(RLMObject *object) {
        if ([weakSelf propertyForColumn: columnIndex].array) {
            [(RLMArray*)selectedInstance[property.name] addObject:object];
        } else {
            selectedInstance[property.name] = object;
        }
    }];
}

- (void)removeObjectLinksAtRows:(NSIndexSet *)rowIndexes column:(NSInteger)columnIndex
{
    [self removeContentsAtRows:rowIndexes column:columnIndex];
}

- (void)removeArrayLinksAtRows:(NSIndexSet *)rowIndexes column:(NSInteger)columnIndex
{
    [self removeContentsAtRows:rowIndexes column:columnIndex];
}

// Opening an array in a new window
- (void)openArrayInNewWindowAtRow:(NSInteger)row column:(NSInteger)column
{
    NSInteger propertyIndex = [self propertyIndexForColumn:column];
    RLMClassProperty *propertyNode = self.displayedType.propertyColumns[propertyIndex];
    RLMArrayNavigationState *state = [[RLMArrayNavigationState alloc] initWithSelectedType:self.displayedType
                                                                                 typeIndex:row
                                                                                  property:propertyNode.property
                                                                                arrayIndex:0];
    
    [self.parentWindowController newWindowWithNavigationState:state];
}

#pragma mark - Private Methods - RLMTableView Delegate Helpers

+ (RLMObject *)createObjectInRealm:(RLMRealm *)realm withSchema:(RLMObjectSchema *)schema
{
    NSMutableDictionary *objectBlueprint = [self defaultValuesForSchema:schema];
    RLMProperty *primaryKey = schema.primaryKeyProperty;
    
    if (primaryKey) {
        id uniqueValue = [self uniqueValueForProperty:primaryKey className:schema.className inRealm:realm];
        if (!uniqueValue) {
            return nil;
        }
        
        objectBlueprint[primaryKey.name] = uniqueValue;
    }
    
    return [realm createObject:schema.className withValue:objectBlueprint];
}

+ (id)uniqueValueForProperty:(RLMProperty *)primaryKey className:(NSString *)className inRealm:(RLMRealm *)realm
{
    NSUInteger remainingAttempts = 100;
    NSUInteger maxBitsUsed = 8;
    
    while (remainingAttempts > 0) {
        id uniqueValue;
        
        if (primaryKey.type == RLMPropertyTypeInt) {
            u_int32_t maxInt = MIN(1 << maxBitsUsed++, UINT32_MAX);
            uniqueValue = @(arc4random_uniform(maxInt));
        } else if (primaryKey.type == RLMPropertyTypeString) {
            uniqueValue = [[NSUUID UUID] UUIDString];
        }
        
        if ([[realm objects:className where:@"%K == %@", primaryKey.name, uniqueValue] count] == 0) {
            return uniqueValue;
        }

        remainingAttempts--;
    }
    
    return nil;
}

+ (NSMutableDictionary *)defaultValuesForSchema:(RLMObjectSchema *)schema
{
    NSMutableDictionary *defaultValues = [NSMutableDictionary dictionary];
    for (RLMProperty *property in schema.properties) {
        defaultValues[property.name] = property.array ? @[] : [self defaultValueForPropertyType:property.type];
    }

    return defaultValues;
}

+ (id)defaultValueForPropertyType:(RLMPropertyType)propertyType
{
    switch (propertyType) {
        case RLMPropertyTypeInt:
            return @0;
        
        case RLMPropertyTypeFloat:
            return @0.0f;

        case RLMPropertyTypeDouble:
            return @0.0;
            
        case RLMPropertyTypeString:
            return @"";
            
        case RLMPropertyTypeBool:
            return @NO;
            
        case RLMPropertyTypeDate:
            return [NSDate date];
            
        case RLMPropertyTypeData:
            return [@"<Data>" dataUsingEncoding:NSUTF8StringEncoding];
            
        case RLMPropertyTypeAny:
            return @"<Any>";
            
        case RLMPropertyTypeObject:
            return [NSNull null];

        case RLMPropertyTypeLinkingObjects:
            return [NSNull null];

        case RLMPropertyTypeObjectId:
        case RLMPropertyTypeDecimal128:
        case RLMPropertyTypeUUID:
            return [NSNull null];
    }
}

- (RLMProperty *)propertyForColumn:(NSInteger)column
{
    NSInteger propertyIndex = [self propertyIndexForColumn:column];

    RLMRealm *realm = self.parentWindowController.document.presentedRealm.realm;
    RLMObjectSchema *objectSchema = [realm.schema schemaForClassName:self.displayedType.name];
    return objectSchema.properties[propertyIndex];
}

- (BOOL)cellsAreNonEmptyInRows:(NSIndexSet *)rowIndexes propertyColumn:(NSInteger)propertyColumn
{
    RLMClassProperty *classProperty = self.displayedType.propertyColumns[propertyColumn];
    
    __block BOOL returnValue = NO;
    
    [rowIndexes enumerateIndexesUsingBlock:^(NSUInteger rowIndex, BOOL *stop) {
        RLMObject *selectedInstance = [self.displayedType instanceAtIndex:rowIndex];
        id propertyValue = selectedInstance[classProperty.name];
        if (propertyValue) {
            returnValue = YES;
            *stop = YES;
        }
    }];
    
    return returnValue;
}

- (void)removeContentsAtRows:(NSIndexSet *)rowIndexes column:(NSInteger)column
{
    NSInteger propertyIndex = [self propertyIndexForColumn:column];
    
    RLMRealm *realm = self.parentWindowController.document.presentedRealm.realm;
    RLMClassProperty *classProperty = self.displayedType.propertyColumns[propertyIndex];
    
    id newValue = classProperty.property.array ? @[] : [NSNull null];

    [realm beginWriteTransaction];
    [rowIndexes enumerateIndexesUsingBlock:^(NSUInteger rowIndex, BOOL *stop) {
        RLMObject *selectedInstance = [self.displayedType instanceAtIndex:rowIndex];
        selectedInstance[classProperty.name] = newValue;
    }];
    [realm commitWriteTransaction];
    // The change notification reloads all windows.
}

#pragma mark - Rearranging objects in arrays - Private methods

- (void)removeRowsInRealmAt:(NSIndexSet *)rowIndexes
{
    RLMRealm *realm = self.parentWindowController.document.presentedRealm.realm;
    
    [realm beginWriteTransaction];
    [rowIndexes enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger index, BOOL *stop) {
        [(RLMArrayNode *)self.displayedType removeInstanceAtIndex:index];
    }];
    [realm commitWriteTransaction];
}

- (void)insertNewRowsInRealmAt:(NSIndexSet *)rowIndexes
{
    if (rowIndexes.count == 0) {
        rowIndexes = [NSIndexSet indexSetWithIndex:0];
    }
    
    RLMRealm *realm = self.parentWindowController.document.presentedRealm.realm;
    
    [realm beginWriteTransaction];

    RLMArrayNode *arrayNode = (RLMArrayNode *)self.displayedType;
    if (arrayNode.isObject) {
        [rowIndexes enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger i, BOOL *stop) {
            RLMObject *object = [self.class createObjectInRealm:realm withSchema:self.displayedType.schema];
            [arrayNode insertInstance:object atIndex:i];
        }];
    }
    else {
        [rowIndexes enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger i, BOOL *stop) {
            [arrayNode insertInstance:[self.class defaultValueForPropertyType:arrayNode.referringProperty.type] atIndex:i];
        }];
    }
    
    [realm commitWriteTransaction];
}

- (void)moveRowsInRealmFrom:(NSIndexSet *)sourceIndexes to:(NSUInteger)destination
{
    RLMRealm *realm = self.parentWindowController.document.presentedRealm.realm;
    
    NSMutableArray *sources = [self arrayWithIndexSet:sourceIndexes];
    
    [realm beginWriteTransaction];
    
    // Iterate through the array, representing source row indices
    for (NSUInteger i = 0; i < sources.count; i++) {
        NSUInteger source = [sources[i] unsignedIntegerValue];
        
        [(RLMArrayNode *)self.displayedType moveInstanceFromIndex:source toIndex:destination];
        
        [self updateSourceIndices:sources afterIndex:i withSource:source destination:&destination];
    }
    
    [realm commitWriteTransaction];
}


- (void)deleteObjectsInRealmAtIndexes:(NSIndexSet *)rowIndexes
{
    if (!self.displayedType.isObject) {
        [self removeRowsInRealmAt:rowIndexes];
        return;
    }

    RLMRealm *realm = self.parentWindowController.document.presentedRealm.realm;
    
    NSMutableArray *objectsToDelete = [NSMutableArray array];
    [rowIndexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
        [objectsToDelete addObject:[self.displayedType instanceAtIndex:index]];
    }];
    
    [realm beginWriteTransaction];
    [realm deleteObjects:objectsToDelete];
    [realm commitWriteTransaction];
}

-(NSMutableArray *)arrayWithIndexSet:(NSIndexSet *)indexSet
{
    NSMutableArray *sources = [NSMutableArray array];
    [indexSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [sources addObject:@(idx)];
    }];
    
    return sources;
}

-(void)updateSourceIndices:(NSMutableArray *)sources
                afterIndex:(NSUInteger)i
                withSource:(NSUInteger)source
               destination:(NSUInteger *)destination
{
    for (NSUInteger j = i + 1; j < sources.count; j++) {
        NSUInteger sourceIndexToModify = [sources[j] unsignedIntegerValue];
        // Everything right of the destination is shifted right
        if (sourceIndexToModify > *destination) {
            sourceIndexToModify++;
        }
        // Everything right of the current source is shifted left
        if (sourceIndexToModify > source) {
            sourceIndexToModify--;
        }
        sources[j] = @(sourceIndexToModify);
    }
    
    // If the move was from higher index to lower, shift destination right
    if (source > *destination) {
        (*destination)++;
    }
}

#pragma mark - Mouse Handling

- (void)mouseDidEnterCellAtLocation:(RLMTableLocation)location
{
    NSInteger propertyIndex = [self propertyIndexForColumn:location.column];
    
    if (propertyIndex >= self.displayedType.propertyColumns.count || location.row >= self.displayedType.instanceCount) {
        [self disableLinkCursor];
        return;
    }
        
    RLMClassProperty *propertyNode = self.displayedType.propertyColumns[propertyIndex];
        
    RLMObject *selectedInstance = [self.displayedType instanceAtIndex:location.row];
    id propertyValue = selectedInstance[propertyNode.name];

    // Tooltips are built here, for just the hovered cell, rather than for every
    // cell in viewForTableColumn: — describing links/arrays walks the linked
    // objects' properties and is far too expensive to run per cell on scroll.
    // There are no cell views; the tooltip is set on the hovered row view and
    // replaced as the mouse moves between that row's cells.
    NSTableRowView *hoveredRowView = [self.tableView rowViewAtRow:location.row makeIfNecessary:NO];
    hoveredRowView.toolTip = [realmDescriptions tooltipForPropertyValue:propertyValue ofType:propertyNode.property];

    if (!propertyValue) {
        [self disableLinkCursor];
        return;
    }

    if (propertyNode.type == RLMPropertyTypeObject || propertyNode.property.array) {
        [self enableLinkCursor];
    }
}

- (void)mouseDidExitCellAtLocation:(RLMTableLocation)location
{
    if (location.row >= 0) {
        [self.tableView rowViewAtRow:location.row makeIfNecessary:NO].toolTip = nil;
    }
    [self disableLinkCursor];
}

- (void)mouseDidExitView:(RLMTableView *)view
{
    [self disableLinkCursor];
}

#pragma mark - Public Methods - NSTableView Event Handling

- (void)rightClickedLocation:(RLMTableLocation)location
{
    NSUInteger row = location.row;

    if (row >= self.displayedType.instanceCount || RLMTableLocationRowIsUndefined(location)) {
        [self clearSelection];
        return;
    }
    
    if ([self.tableView.selectedRowIndexes containsIndex:row]) {
        return;
    }
    
    [self setSelectionIndex:row];
}

- (void)userClicked:(NSTableView *)sender
{
    if (self.tableView.selectedRowIndexes.count > 1) {
        return;
    }
    
    NSInteger row = self.tableView.clickedRow;
    NSInteger column = self.tableView.clickedColumn;
    NSInteger propertyIndex = [self propertyIndexForColumn:column];
    
    if (row == NOT_A_ROW || propertyIndex < 0) {
        return;
    }
    
    RLMClassProperty *propertyNode = self.displayedType.propertyColumns[propertyIndex];
    
    if (propertyNode.type == RLMPropertyTypeObject || propertyNode.property.array) {
        RLMObject *selectedInstance = [self.displayedType instanceAtIndex:row];
        id propertyValue = selectedInstance[propertyNode.name];
        
        if ([propertyValue isKindOfClass:[RLMObject class]]) {
            RLMObject *linkedObject = (RLMObject *)propertyValue;
            RLMObjectSchema *linkedObjectSchema = linkedObject.objectSchema;
            
            for (RLMClassNode *classNode in self.parentWindowController.document.presentedRealm.topLevelClasses) {
                if ([classNode.name isEqualToString:linkedObjectSchema.className]) {
                    RLMResults *allInstances = [linkedObject.realm allObjects:linkedObjectSchema.className];
                    NSUInteger objectIndex = [allInstances indexOfObject:linkedObject];
                    
                    RLMNavigationState *state = [[RLMNavigationState alloc] initWithSelectedType:classNode index:objectIndex];
                    [self.parentWindowController addNavigationState:state fromViewController:self];
                    
                    break;
                }
            }
        }
        else if ([propertyValue isKindOfClass:[RLMArray class]]) {
            RLMArrayNavigationState *state = [[RLMArrayNavigationState alloc] initWithSelectedType:self.displayedType
                                                                                         typeIndex:row
                                                                                          property:propertyNode.property
                                                                                        arrayIndex:0];
            [self.parentWindowController addNavigationState:state fromViewController:self];
        }
    }
    else {
        [self setSelectionIndex:row];
    }
}

- (void)userDoubleClicked:(NSTableView *)sender
{
    [self beginInlineEditingAtRow:self.tableView.clickedRow column:self.tableView.clickedColumn];
}

#pragma mark - Inline editing

// Primitive-array rows are represented by a proxy rather than a real object;
// they have no primary key (and no objectSchema to ask).
- (BOOL)isPrimaryKeyProperty:(RLMProperty *)property ofInstance:(RLMObject *)instance
{
    if (![instance isKindOfClass:[RLMObject class]]) {
        return NO;
    }
    return [property.name isEqualToString:instance.objectSchema.primaryKeyProperty.name];
}

- (BOOL)canInlineEditProperty:(RLMClassProperty *)classProperty ofInstance:(RLMObject *)instance
{
    if (classProperty == nil || classProperty.property.array) {
        return NO;
    }
    switch (classProperty.type) {
        case RLMPropertyTypeInt:
        case RLMPropertyTypeFloat:
        case RLMPropertyTypeDouble:
        case RLMPropertyTypeString:
            break;
        default:
            return NO;
    }
    return ![self isPrimaryKeyProperty:classProperty.property ofInstance:instance];
}

// The drawn-text cells host no text fields, so one shared editor overlays the
// cell for the duration of an edit.
- (NSTextField *)inlineEditorField
{
    if (_inlineEditorField == nil) {
        NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
        field.font = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightRegular];
        field.bezeled = NO;
        field.bordered = NO;
        field.drawsBackground = YES;
        field.backgroundColor = NSColor.textBackgroundColor;
        [(NSTextFieldCell *)field.cell setScrollable:YES];
        [(NSTextFieldCell *)field.cell setUsesSingleLineMode:YES];
        field.cell.sendsActionOnEndEditing = YES;
        field.target = self;
        field.action = @selector(inlineEditorAction:);
        field.delegate = self;
        _inlineEditorField = field;
    }
    return _inlineEditorField;
}

+ (NSNumberFormatter *)inlineEditingNumberFormatter
{
    static NSNumberFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        formatter.maximumFractionDigits = UINT16_MAX;
        formatter.hasThousandSeparators = NO;
    });
    return formatter;
}

- (void)beginInlineEditingAtRow:(NSInteger)row column:(NSInteger)column
{
    if (row == NOT_A_ROW || column == NOT_A_COLUMN) {
        return;
    }

    NSInteger propertyIndex = [self propertyIndexForColumn:column];
    if (propertyIndex < 0 || propertyIndex >= (NSInteger)self.displayedType.propertyColumns.count) {
        return;
    }

    RLMClassProperty *classProperty = self.displayedType.propertyColumns[propertyIndex];
    RLMObject *instance = [self.displayedType instanceAtIndex:row];
    if (![self canInlineEditProperty:classProperty ofInstance:instance]) {
        return;
    }

    NSTableRowView *rowView = [self.tableView rowViewAtRow:row makeIfNecessary:NO];
    if (rowView == nil) {
        return;
    }

    [self discardInlineEditing];

    id value = instance[classProperty.name];
    if (value == NSNull.null) {
        value = nil;
    }

    NSTextField *field = self.inlineEditorField;
    if (classProperty.type == RLMPropertyTypeString) {
        field.formatter = nil;
        field.stringValue = value ?: @"";
    }
    else {
        field.formatter = [self.class inlineEditingNumberFormatter];
        field.objectValue = value;
    }

    field.frame = [rowView convertRect:[self.tableView frameOfCellAtColumn:column row:row] fromView:self.tableView];
    [rowView addSubview:field];
    inlineEditingRow = row;
    inlineEditingColumn = column;

    self.inlineEditingActive = YES;
    self.inlineEditingCancelled = NO;
    [self.view.window makeFirstResponder:field];
}

- (void)discardInlineEditing
{
    if (!self.inlineEditingActive) {
        return;
    }
    self.inlineEditingActive = NO;
    inlineEditingRow = NOT_A_ROW;
    inlineEditingColumn = NOT_A_COLUMN;
    [self removeInlineEditor];
}

- (void)removeInlineEditor
{
    if (_inlineEditorField.superview == nil) {
        return;
    }
    if (_inlineEditorField.currentEditor != nil) {
        // Ends the field-editor session; the resulting action is a no-op since
        // inlineEditingActive has already been cleared by the caller.
        [self.view.window makeFirstResponder:self.tableView];
    }
    [_inlineEditorField removeFromSuperview];
}

- (void)inlineEditorAction:(NSTextField *)sender
{
    if (!self.inlineEditingActive) {
        return;
    }
    self.inlineEditingActive = NO;

    BOOL cancelled = self.inlineEditingCancelled;
    // The editor is a direct subview of the row view, so columnForView: cannot
    // recover the column; both were recorded when editing began.
    NSInteger row = inlineEditingRow;
    NSInteger column = inlineEditingColumn;
    inlineEditingRow = NOT_A_ROW;
    inlineEditingColumn = NOT_A_COLUMN;
    id enteredNumber = sender.objectValue;
    NSString *enteredString = sender.stringValue;

    [self removeInlineEditor];

    if (cancelled || row == NOT_A_ROW || column == NOT_A_COLUMN) {
        return;
    }

    NSInteger propertyIndex = [self propertyIndexForColumn:column];
    if (propertyIndex < 0 || propertyIndex >= (NSInteger)self.displayedType.propertyColumns.count) {
        return;
    }

    RLMClassProperty *classProperty = self.displayedType.propertyColumns[propertyIndex];
    RLMObject *instance = [self.displayedType instanceAtIndex:row];
    if ([instance respondsToSelector:@selector(isInvalidated)] && instance.isInvalidated) {
        return;
    }

    id newValue;
    switch (classProperty.type) {
        case RLMPropertyTypeInt:
            // The formatter parses freely; clamp to an integral value.
            newValue = [enteredNumber isKindOfClass:[NSNumber class]] ? @([enteredNumber longLongValue]) : nil;
            break;
        case RLMPropertyTypeFloat:
        case RLMPropertyTypeDouble:
            newValue = [enteredNumber isKindOfClass:[NSNumber class]] ? enteredNumber : nil;
            break;
        case RLMPropertyTypeString:
            newValue = enteredString;
            break;
        default:
            return;
    }

    if (newValue == nil && !classProperty.property.optional) {
        NSBeep();
        return;
    }

    id currentValue = instance[classProperty.name];
    if (currentValue == NSNull.null) {
        currentValue = nil;
    }
    if (currentValue == newValue || [currentValue isEqual:newValue]) {
        return;
    }

    RLMRealm *realm = self.parentWindowController.document.presentedRealm.realm;
    [realm beginWriteTransaction];
    @try {
        instance[classProperty.name] = newValue;
        [realm commitWriteTransaction];
        // The realm change notification triggers the table reload.
    }
    @catch (NSException *exception) {
        [realm cancelWriteTransaction];
        NSBeep();
    }
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    if (control == _inlineEditorField && commandSelector == @selector(cancelOperation:)) {
        self.inlineEditingCancelled = YES;
        [self.view.window makeFirstResponder:self.tableView];
        return YES;
    }
    return NO;
}

#pragma mark - Public Methods - Table View Construction

- (void)enableLinkCursor
{
    if (linkCursorDisplaying) {
        return;
    }
    NSCursor *currentCursor = [NSCursor currentCursor];
    [currentCursor push];
    
    NSCursor *newCursor = [NSCursor pointingHandCursor];
    [newCursor set];
    
    linkCursorDisplaying = YES;
}

- (void)disableLinkCursor
{
    if (!linkCursorDisplaying) {
        return;
    }
    
    [NSCursor pop];
    linkCursorDisplaying = NO;
}

#pragma mark - Private Methods - Convenience

-(NSInteger)propertyIndexForColumn:(NSInteger)column
{
    return self.displaysArray ? column - 1 : column;
}

@end
