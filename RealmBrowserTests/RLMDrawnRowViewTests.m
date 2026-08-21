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

@interface RLMDrawnRowViewTests : XCTestCase
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

@end
