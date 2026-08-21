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
#import "RLMTypeNode.h"

@class RLMClassProperty;

@interface RLMTableColumn : NSTableColumn

@property (nonatomic) RLMPropertyType propertyType;

// Set when the column represents a schema property; used to compute the
// header statistics tooltip lazily on first hover rather than at column setup.
@property (nonatomic, strong) RLMClassProperty *classProperty;
@property (nonatomic, copy) NSString *cachedHeaderToolTip;

- (CGFloat)sizeThatFitsWithLimit:(BOOL)limited;

// Width needed to show the header title and the given rows' content
// untruncated. Used for the fill-out pass with the on-screen row range.
- (CGFloat)widthThatFitsRows:(NSRange)rowRange;

@end
