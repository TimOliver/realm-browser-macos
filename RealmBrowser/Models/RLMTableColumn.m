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

#import "RLMTableColumn.h"
#import "RLMTableCellView.h"
#import "RLMTableView.h"
#import "RLMClassProperty.h"
#import "RLMDescriptions.h"

@implementation RLMTableColumn

@synthesize cellReuseIdentifier = _cellReuseIdentifier;

const NSUInteger kMaxNumberOfRowsToConsider = 50;
const CGFloat kMaxColumnWidth = 200.0;

- (NSString *)cellReuseIdentifier
{
    if (_cellReuseIdentifier == nil && self.classProperty != nil) {
        RLMProperty *property = self.classProperty.property;
        _cellReuseIdentifier = [NSString stringWithFormat:@"Property.%@.Optional.%d",
                                [RLMDescriptions typeNameOfProperty:property], property.optional];
    }
    return _cellReuseIdentifier;
}

- (CGFloat)sizeThatFitsWithLimit:(BOOL)limited
{
    int rowsToConsider = 1;

    switch (self.propertyType) {
        case RLMPropertyTypeBool:
        case RLMPropertyTypeData:
        case RLMPropertyTypeAny:
            rowsToConsider = 1;
            break;

        case RLMPropertyTypeObject:
        case RLMPropertyTypeDate:
        case RLMPropertyTypeLinkingObjects:
        case RLMPropertyTypeObjectId:
        case RLMPropertyTypeDecimal128:
        case RLMPropertyTypeUUID:
            rowsToConsider = 3;
            break;

        case RLMPropertyTypeInt:
        case RLMPropertyTypeFloat:
        case RLMPropertyTypeDouble:
        case RLMPropertyTypeString:
            rowsToConsider = kMaxNumberOfRowsToConsider;
            break;
    }

    // Measure the formatted strings directly. Instantiating real cell views and
    // asking each for its fittingSize forces an Auto Layout pass per cell, which
    // is far too slow to run for every column of a newly displayed class.
    id<RLMTableViewDataSource> dataSource = (id<RLMTableViewDataSource>)self.tableView.dataSource;
    NSInteger rowCount = [dataSource numberOfRowsInTableView:self.tableView];

    static NSDictionary *textAttributes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        textAttributes = @{NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightRegular]};
    });

    CGFloat maxWidth = 0.0;

    if (self.classProperty == nil) {
        // The array-index gutter column; size for the largest row number.
        maxWidth = ceil([[@(MAX(rowCount, 1)) stringValue] sizeWithAttributes:textAttributes].width);
    }
    else if (self.propertyType == RLMPropertyTypeBool && !self.classProperty.property.array) {
        maxWidth = 24.0; // Fixed-size checkbox
    }
    else {
        for (NSInteger rowIndex = 0; rowIndex < MIN(rowsToConsider, rowCount); rowIndex++) {
            NSString *text = [dataSource displayedStringForColumn:self.classProperty row:rowIndex];
            maxWidth = MAX(maxWidth, ceil([text sizeWithAttributes:textAttributes].width));
        }
        if (self.classProperty.property.array) {
            maxWidth += 44.0; // Count badge and its leading gap
        }
    }


    NSCell *headerCell = self.headerCell;
    NSRect rect = NSMakeRect(0,0, INFINITY, self.tableView.rowHeight);
    NSSize headerSize = [headerCell cellSizeForBounds:rect];

    maxWidth = MAX(maxWidth + 10.0f, headerSize.width*1.1);

    CGFloat initialFloor = 0.0;
    switch (self.propertyType) {
        case RLMPropertyTypeString:
            initialFloor = 128.0;
            break;
        case RLMPropertyTypeInt:
        case RLMPropertyTypeFloat:
        case RLMPropertyTypeDouble:
            initialFloor = 64.0;
            break;
        default:
            break;
    }
    maxWidth = MAX(maxWidth, initialFloor);

    if (limited) {
        maxWidth = MIN(maxWidth, kMaxColumnWidth);
    }

    return maxWidth;
}

@end
