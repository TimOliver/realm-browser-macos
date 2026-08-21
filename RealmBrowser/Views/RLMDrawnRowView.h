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

// AppKit declares this on NSTableCellView only, and builds a row's drag image from
// the cell views it finds. There are none here, so the row snapshots itself; the
// declaration is repeated so callers (and tests) can see it.
@property (nonatomic, readonly, strong) NSArray<NSDraggingImageComponent *> *draggingImageComponents;

@end
