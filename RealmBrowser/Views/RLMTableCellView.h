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

@interface RLMTableCellView : NSTableCellView

@property (nonatomic, assign) BOOL optional;

// Drawn directly in drawRect — text cells host no NSTextField, which is what
// keeps scrolling cheap. nil means the cell doesn't use drawn text (bool/popup
// cells); an empty string draws the "nil" placeholder when `optional` is set.
@property (nonatomic, copy) NSString *text;

+ (instancetype)viewWithIdentifier:(NSString *)identifier;

// Override points for subclasses (link styling, badge inset).
- (NSDictionary *)textAttributes;
- (NSRect)textDrawingRect;

@end
