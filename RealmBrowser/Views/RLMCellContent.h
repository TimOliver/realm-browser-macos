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
