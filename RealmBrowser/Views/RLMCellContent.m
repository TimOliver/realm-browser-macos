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
    // Object links are always optional in Realm, so an empty link draws the "nil"
    // placeholder, as the link cell views used to.
    return [[self alloc] initWithKind:RLMCellContentKindLink text:text placeholder:YES boolValue:NO badgeText:nil];
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
