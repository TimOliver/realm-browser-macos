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

@import Realm.Private;

#import "RLMDocument.h"
#import "RLMBrowserConstants.h"
#import "RLMRealmBrowserWindowController.h"

@interface RLMDocument ()

@property (nonatomic, strong) NSError *error;

@end

@implementation RLMDocument

- (instancetype)initWithContentsOfURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
    if (![typeName.lowercaseString isEqualToString:kRealmUTIIdentifier]) {
        return nil;
    }

    if (!absoluteURL.isFileURL) {
        return nil;
    }

    return [self initWithContentsOfFileURL:absoluteURL error:outError];
}

- (instancetype)initWithContentsOfFileURL:(NSURL *)fileURL error:(NSError **)outError {
    if (![fileURL.pathExtension.lowercaseString isEqualToString:kRealmFileExtension]) {
        return nil;
    }

    BOOL isDir = NO;
    if (!([[NSFileManager defaultManager] fileExistsAtPath:fileURL.path isDirectory:&isDir] && isDir == NO)) {
        return nil;
    }

    self = [super init];

    if (self != nil) {
        self.fileURL = fileURL;

        self.presentedRealm = [[RLMRealmNode alloc] initWithFileURL:self.fileURL];

        if (![self loadWithError:outError] && self.state == RLMDocumentStateUnrecoverableError) {
            return nil;
        }
    }

    return self;
}

- (BOOL)loadByPerformingFormatUpgradeWithError:(NSError **)error {
    NSAssert(self.state == RLMDocumentStateRequiresFormatUpgrade, @"Invalid document state");

    self.presentedRealm.disableFormatUpgrade = NO;

    return [self loadWithError:error];
}

- (BOOL)loadWithEncryptionKey:(NSData *)key error:(NSError **)error {
    NSAssert(self.state == RLMDocumentStateNeedsEncryptionKey, @"Invalid document state");

    self.presentedRealm.encryptionKey = key;

    return [self loadWithError:error];
}

- (BOOL)loadWithError:(NSError **)outError {
    NSAssert(self.presentedRealm != nil, @"Presented Realm must be created before loading");

    NSError *error;
    if ([self.presentedRealm connect:&error]) {
        self.state = RLMDocumentStateLoaded;
        self.error = nil;

        return YES;
    } else {
        switch (error.code) {
            case RLMErrorFileAccess:
            self.state = RLMDocumentStateNeedsEncryptionKey;
            break;

            case RLMErrorFileFormatUpgradeRequired:
            self.state = RLMDocumentStateRequiresFormatUpgrade;
            break;

            default:
            self.state = RLMDocumentStateUnrecoverableError;
            break;
        }

        self.error = error;

        if (outError != nil) {
            *outError = error;
        }

        return NO;
    }
}

#pragma mark NSDocument overrides

- (void)makeWindowControllers
{
    RLMRealmBrowserWindowController *windowController = [[RLMRealmBrowserWindowController alloc] initWithWindowNibName:self.windowNibName];
    [self addWindowController:windowController];
}

- (NSString *)windowNibName
{
    return @"RLMDocument";
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
    // As we do not use the usual file handling mechanism we just returns nil (but it is necessary
    // to override this method as the default implementation throws an exception.
    return nil;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
    // As we do not use the usual file handling mechanism we just returns YES (but it is necessary
    // to override this method as the default implementation throws an exception.
    return YES;
}

- (NSString *)displayName
{
    return self.fileURL.lastPathComponent;
}

@end
