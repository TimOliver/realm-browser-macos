////////////////////////////////////////////////////////////////////////////
//
// Copyright 2026 Realm Browser Contributors
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

#import "RLMInspectorViewController.h"

static const CGFloat kRowVerticalSpacing = 12.0;
static const CGFloat kHorizontalInset = 16.0;

@interface RLMFlippedView : NSView
@end

@implementation RLMFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface RLMInspectorViewController () <NSTextFieldDelegate>

@property (nonatomic, strong) NSStackView *headerStack;
@property (nonatomic, strong) NSBox *headerSeparator;
@property (nonatomic, strong) NSTextField *headerTitleLabel;
@property (nonatomic, strong) NSTextField *headerSubtitleLabel;
@property (nonatomic, strong) NSStackView *fieldsStack;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTextField *emptyStateLabel;

@property (nonatomic, weak) RLMObject *inspectedObject;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *stagedValues;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSControl *> *editorsByPropertyName;

@end

@implementation RLMInspectorViewController

- (instancetype)init
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _stagedValues = [NSMutableDictionary dictionary];
        _editorsByPropertyName = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)loadView
{
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 480)];

    // Scroll view with the stack of field rows.
    self.fieldsStack = [[NSStackView alloc] init];
    self.fieldsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.fieldsStack.alignment = NSLayoutAttributeLeading;
    self.fieldsStack.spacing = kRowVerticalSpacing;
    self.fieldsStack.edgeInsets = NSEdgeInsetsMake(kRowVerticalSpacing, kHorizontalInset, kRowVerticalSpacing, kHorizontalInset);
    self.fieldsStack.translatesAutoresizingMaskIntoConstraints = NO;

    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.drawsBackground = NO;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;

    RLMFlippedView *documentView = [[RLMFlippedView alloc] init];
    documentView.translatesAutoresizingMaskIntoConstraints = NO;
    [documentView addSubview:self.fieldsStack];
    self.scrollView.documentView = documentView;

    // Header with "Properties" title + "{Type} / {PK or first field}" subtitle.
    self.headerTitleLabel = [NSTextField labelWithString:@"Properties"];
    self.headerTitleLabel.font = [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold];
    self.headerTitleLabel.textColor = NSColor.labelColor;
    self.headerTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.headerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.headerSubtitleLabel = [NSTextField labelWithString:@""];
    self.headerSubtitleLabel.font = [NSFont systemFontOfSize:11];
    self.headerSubtitleLabel.textColor = NSColor.secondaryLabelColor;
    self.headerSubtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.headerSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *titleStack = [NSStackView stackViewWithViews:@[self.headerTitleLabel, self.headerSubtitleLabel]];
    titleStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    titleStack.alignment = NSLayoutAttributeLeading;
    titleStack.spacing = 2;
    titleStack.edgeInsets = NSEdgeInsetsMake(12, kHorizontalInset, 12, kHorizontalInset);
    titleStack.translatesAutoresizingMaskIntoConstraints = NO;

    self.headerSeparator = [[NSBox alloc] init];
    self.headerSeparator.boxType = NSBoxSeparator;
    self.headerSeparator.translatesAutoresizingMaskIntoConstraints = NO;

    // Outer stack collapses when its arranged subviews are hidden, letting the scroll view rise to the top.
    self.headerStack = [NSStackView stackViewWithViews:@[titleStack, self.headerSeparator]];
    self.headerStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.headerStack.alignment = NSLayoutAttributeLeading;
    self.headerStack.distribution = NSStackViewDistributionFill;
    self.headerStack.spacing = 0;
    self.headerStack.translatesAutoresizingMaskIntoConstraints = NO;

    // Empty state label shown when no row is selected.
    self.emptyStateLabel = [NSTextField labelWithString:@"No Selection"];
    self.emptyStateLabel.font = [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightRegular];
    self.emptyStateLabel.textColor = NSColor.secondaryLabelColor;
    self.emptyStateLabel.alignment = NSTextAlignmentCenter;
    self.emptyStateLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [container addSubview:self.headerStack];
    [container addSubview:self.scrollView];
    [container addSubview:self.emptyStateLabel];

    [NSLayoutConstraint activateConstraints:@[
        // Header pinned to top, full width.
        [self.headerStack.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.headerStack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.headerStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.headerSeparator.leadingAnchor constraintEqualToAnchor:self.headerStack.leadingAnchor],
        [self.headerSeparator.trailingAnchor constraintEqualToAnchor:self.headerStack.trailingAnchor],

        // Scroll view starts right below the header stack (which collapses to 0 when hidden).
        [self.scrollView.topAnchor constraintEqualToAnchor:self.headerStack.bottomAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

        // Stack view fills the scroll view's document view (vertical scroll only)
        [self.fieldsStack.topAnchor constraintEqualToAnchor:documentView.topAnchor],
        [self.fieldsStack.leadingAnchor constraintEqualToAnchor:documentView.leadingAnchor],
        [self.fieldsStack.trailingAnchor constraintEqualToAnchor:documentView.trailingAnchor],
        [self.fieldsStack.bottomAnchor constraintEqualToAnchor:documentView.bottomAnchor],
        [documentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],

        // Empty state centered in the scroll view area
        [self.emptyStateLabel.centerXAnchor constraintEqualToAnchor:self.scrollView.centerXAnchor],
        [self.emptyStateLabel.centerYAnchor constraintEqualToAnchor:self.scrollView.centerYAnchor],
    ]];

    self.view = container;
    [self updateHeader];
    [self updateEmptyStateVisibility];
}

#pragma mark - Public API

- (void)setInspectedObject:(RLMObject *)object
{
    _inspectedObject = object;
    [self.stagedValues removeAllObjects];
    [self rebuildEditors];
    [self updateHeader];
    [self updateEmptyStateVisibility];
}

- (void)updateHeader
{
    RLMObject *object = self.inspectedObject;
    if (!object || object.isInvalidated) {
        self.headerSubtitleLabel.stringValue = @"";
        return;
    }

    NSString *className = object.objectSchema.className ?: @"";
    RLMProperty *subtitleProperty = object.objectSchema.primaryKeyProperty ?: object.objectSchema.properties.firstObject;
    NSString *valueDescription = @"";
    if (subtitleProperty) {
        id value = object[subtitleProperty.name];
        if (value && value != NSNull.null) {
            valueDescription = [NSString stringWithFormat:@"%@", value];
        }
    }

    if (valueDescription.length > 0) {
        self.headerSubtitleLabel.stringValue = [NSString stringWithFormat:@"%@  /  %@", className, valueDescription];
    } else {
        self.headerSubtitleLabel.stringValue = className;
    }
}

#pragma mark - Editor construction

- (void)rebuildEditors
{
    for (NSView *subview in self.fieldsStack.arrangedSubviews.copy) {
        [self.fieldsStack removeArrangedSubview:subview];
        [subview removeFromSuperview];
    }
    [self.editorsByPropertyName removeAllObjects];

    RLMObject *object = self.inspectedObject;
    if (!object || object.isInvalidated) {
        return;
    }

    NSString *primaryKeyName = object.objectSchema.primaryKeyProperty.name;
    for (RLMProperty *property in object.objectSchema.properties) {
        BOOL isPrimaryKey = [property.name isEqualToString:primaryKeyName];
        NSView *row = [self rowForProperty:property value:object[property.name] isPrimaryKey:isPrimaryKey];
        if (row) {
            [self.fieldsStack addArrangedSubview:row];
            [row.widthAnchor constraintEqualToAnchor:self.fieldsStack.widthAnchor constant:-(2 * kHorizontalInset)].active = YES;
        }
    }
}

- (nullable NSView *)rowForProperty:(RLMProperty *)property value:(id)value isPrimaryKey:(BOOL)isPrimaryKey
{
    NSString *labelText = isPrimaryKey ? [property.name stringByAppendingString:@"  (Primary Key)"] : property.name;
    NSTextField *nameLabel = [NSTextField labelWithString:labelText];
    nameLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    nameLabel.textColor = NSColor.secondaryLabelColor;
    nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *typeLabel = [NSTextField labelWithString:[self uppercaseTypeNameForProperty:property]];
    typeLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    typeLabel.textColor = NSColor.tertiaryLabelColor;
    typeLabel.alignment = NSTextAlignmentRight;
    typeLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    typeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [typeLabel setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    [typeLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *labelRow = [NSStackView stackViewWithViews:@[nameLabel, typeLabel]];
    labelRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    labelRow.distribution = NSStackViewDistributionFill;
    labelRow.alignment = NSLayoutAttributeFirstBaseline;
    labelRow.spacing = 8;
    labelRow.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *editor = [self editorForProperty:property value:value isPrimaryKey:isPrimaryKey];
    editor.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *row = [[NSStackView alloc] init];
    row.orientation = NSUserInterfaceLayoutOrientationVertical;
    row.alignment = NSLayoutAttributeLeading;
    row.spacing = 4;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row addArrangedSubview:labelRow];
    [row addArrangedSubview:editor];

    [labelRow.widthAnchor constraintEqualToAnchor:row.widthAnchor].active = YES;
    [editor.widthAnchor constraintEqualToAnchor:row.widthAnchor].active = YES;

    return row;
}

- (NSString *)uppercaseTypeNameForProperty:(RLMProperty *)property
{
    NSString *base = nil;
    switch (property.type) {
        case RLMPropertyTypeBool:           base = @"Bool"; break;
        case RLMPropertyTypeInt:            base = @"Int"; break;
        case RLMPropertyTypeFloat:          base = @"Float"; break;
        case RLMPropertyTypeDouble:         base = @"Double"; break;
        case RLMPropertyTypeString:         base = @"String"; break;
        case RLMPropertyTypeData:           base = @"Data"; break;
        case RLMPropertyTypeDate:           base = @"Date"; break;
        case RLMPropertyTypeAny:            base = @"Any"; break;
        case RLMPropertyTypeObject:         base = property.objectClassName ?: @"Object"; break;
        case RLMPropertyTypeLinkingObjects: base = property.objectClassName ?: @"LinkingObjects"; break;
        case RLMPropertyTypeObjectId:       base = @"ObjectId"; break;
        case RLMPropertyTypeDecimal128:     base = @"Decimal128"; break;
        case RLMPropertyTypeUUID:           base = @"UUID"; break;
    }
    if (property.array) {
        base = [NSString stringWithFormat:@"[%@]", base];
    }
    return base.uppercaseString;
}

- (NSView *)editorForProperty:(RLMProperty *)property value:(id)value isPrimaryKey:(BOOL)isPrimaryKey
{
    if (property.array || property.type == RLMPropertyTypeLinkingObjects || property.type == RLMPropertyTypeObject) {
        return [self readOnlyTextFieldWithString:[self descriptionForValue:value ofProperty:property]];
    }

    switch (property.type) {
        case RLMPropertyTypeBool:
            return [self checkboxForProperty:property value:value isPrimaryKey:isPrimaryKey];
        case RLMPropertyTypeInt:
        case RLMPropertyTypeFloat:
        case RLMPropertyTypeDouble:
            return [self numberFieldForProperty:property value:value isPrimaryKey:isPrimaryKey];
        case RLMPropertyTypeString:
            return [self stringFieldForProperty:property value:value isPrimaryKey:isPrimaryKey];
        case RLMPropertyTypeDate:
            return [self datePickerForProperty:property value:value isPrimaryKey:isPrimaryKey];
        default:
            return [self readOnlyTextFieldWithString:[self descriptionForValue:value ofProperty:property]];
    }
}

- (NSTextField *)stringFieldForProperty:(RLMProperty *)property value:(id)value isPrimaryKey:(BOOL)isPrimaryKey
{
    NSTextField *field = [NSTextField textFieldWithString:value ?: @""];
    field.editable = !isPrimaryKey;
    field.bezelStyle = NSTextFieldRoundedBezel;
    field.controlSize = NSControlSizeLarge;
    field.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeLarge]];
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    [field.cell setUsesSingleLineMode:YES];
    [field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    field.target = self;
    field.action = @selector(textFieldEdited:);
    field.delegate = self;
    field.identifier = property.name;
    [field.cell setSendsActionOnEndEditing:YES];
    self.editorsByPropertyName[property.name] = field;
    return field;
}

- (NSTextField *)numberFieldForProperty:(RLMProperty *)property value:(id)value isPrimaryKey:(BOOL)isPrimaryKey
{
    NSTextField *field = [NSTextField textFieldWithString:value ? [NSString stringWithFormat:@"%@", value] : @""];
    field.editable = !isPrimaryKey;
    field.bezelStyle = NSTextFieldRoundedBezel;
    field.controlSize = NSControlSizeLarge;
    field.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeLarge]];
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    [field.cell setUsesSingleLineMode:YES];
    [field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.allowsFloats = (property.type != RLMPropertyTypeInt);
    formatter.maximumFractionDigits = (property.type == RLMPropertyTypeInt) ? 0 : NSIntegerMax;
    field.formatter = formatter;

    field.target = self;
    field.action = @selector(textFieldEdited:);
    field.delegate = self;
    field.identifier = property.name;
    [field.cell setSendsActionOnEndEditing:YES];
    self.editorsByPropertyName[property.name] = field;
    return field;
}

- (NSButton *)checkboxForProperty:(RLMProperty *)property value:(id)value isPrimaryKey:(BOOL)isPrimaryKey
{
    NSButton *checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(checkboxToggled:)];
    checkbox.state = [value boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    checkbox.identifier = property.name;
    checkbox.enabled = !isPrimaryKey;
    self.editorsByPropertyName[property.name] = checkbox;
    return checkbox;
}

- (NSDatePicker *)datePickerForProperty:(RLMProperty *)property value:(id)value isPrimaryKey:(BOOL)isPrimaryKey
{
    NSDatePicker *picker = [[NSDatePicker alloc] init];
    picker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    picker.datePickerElements = NSDatePickerElementFlagYearMonthDay | NSDatePickerElementFlagHourMinuteSecond;
    picker.controlSize = NSControlSizeLarge;
    picker.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeLarge]];
    picker.dateValue = value ?: [NSDate date];
    picker.target = self;
    picker.action = @selector(datePickerChanged:);
    picker.identifier = property.name;
    picker.enabled = !isPrimaryKey;
    [picker setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.editorsByPropertyName[property.name] = (id)picker;
    return picker;
}

- (NSTextField *)readOnlyTextFieldWithString:(NSString *)string
{
    NSTextField *field = [NSTextField labelWithString:string ?: @""];
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    field.textColor = NSColor.labelColor;
    [field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return field;
}

- (NSString *)descriptionForValue:(id)value ofProperty:(RLMProperty *)property
{
    if (!value || value == NSNull.null) {
        return @"—";
    }
    if (property.array) {
        return [NSString stringWithFormat:@"%@[%lu]", property.objectClassName ?: @"", (unsigned long)[value count]];
    }
    if (property.type == RLMPropertyTypeObject) {
        return [NSString stringWithFormat:@"<%@>", property.objectClassName];
    }
    if ([value respondsToSelector:@selector(description)]) {
        return [value description];
    }
    return @"";
}

#pragma mark - Editor callbacks

- (void)textFieldEdited:(NSTextField *)sender
{
    NSString *name = sender.identifier;
    if (!name) {
        return;
    }
    RLMProperty *property = [self.inspectedObject.objectSchema[name] copy];
    id staged = nil;
    switch (property.type) {
        case RLMPropertyTypeInt:
        case RLMPropertyTypeFloat:
        case RLMPropertyTypeDouble:
            staged = sender.objectValue;
            break;
        case RLMPropertyTypeString:
        default:
            staged = sender.stringValue;
            break;
    }
    [self stageValue:staged forPropertyName:name];
}

- (void)checkboxToggled:(NSButton *)sender
{
    NSString *name = sender.identifier;
    if (!name) {
        return;
    }
    [self stageValue:@(sender.state == NSControlStateValueOn) forPropertyName:name];
}

- (void)datePickerChanged:(NSDatePicker *)sender
{
    NSString *name = sender.identifier;
    if (!name) {
        return;
    }
    [self stageValue:sender.dateValue forPropertyName:name];
}

- (void)stageValue:(id)value forPropertyName:(NSString *)name
{
    if (!value) {
        [self.stagedValues removeObjectForKey:name];
    } else {
        self.stagedValues[name] = value;
    }
}

#pragma mark - Commit / discard (keyboard-triggered)

- (void)commitStagedChanges
{
    RLMObject *object = self.inspectedObject;
    if (!object || object.isInvalidated || self.stagedValues.count == 0) {
        return;
    }

    NSDictionary *values = [self.stagedValues copy];
    RLMRealm *realm = object.realm;
    NSError *error = nil;
    [realm beginWriteTransaction];
    [values enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        object[key] = value;
    }];
    if (![realm commitWriteTransaction:&error]) {
        [NSApp presentError:error];
    }

    [self.stagedValues removeAllObjects];
    [self rebuildEditors];
}

- (void)discardStagedChanges
{
    [self.stagedValues removeAllObjects];
    [self rebuildEditors];
}

#pragma mark - NSTextFieldDelegate (Return / Escape)

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    if (commandSelector == @selector(insertNewline:)) {
        // End editing so the field's action fires and the value is staged, then commit everything.
        [self.view.window makeFirstResponder:self.view];
        [self commitStagedChanges];
        return YES;
    }
    if (commandSelector == @selector(cancelOperation:)) {
        [self discardStagedChanges];
        return YES;
    }
    return NO;
}

- (void)cancelOperation:(id)sender
{
    [self discardStagedChanges];
}

- (void)insertNewline:(id)sender
{
    [self commitStagedChanges];
}

- (void)updateEmptyStateVisibility
{
    BOOL empty = (self.inspectedObject == nil || self.inspectedObject.isInvalidated);
    self.emptyStateLabel.hidden = !empty;
    self.scrollView.hidden = empty;
    self.headerStack.hidden = empty;
}

@end
