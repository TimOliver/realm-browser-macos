# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Realm Browser is a document-based macOS AppKit app (Objective-C) for opening `.realm` database files to view and modify their contents. Originally a Realm Inc. project, it was deprecated in favor of Realm Studio and has since been revived and modernized: version 4.0, macOS 11+ deployment target, Realm 20.x via CocoaPods, Hardened Runtime enabled. Ignore the struck-through deprecation notice in the README — this app is actively developed again.

## Building

Dependencies come from CocoaPods, so always build the **workspace**, and note the scheme name contains a space:

```bash
pod install
xcodebuild -workspace RealmBrowser.xcworkspace -scheme 'Realm Browser' -configuration Debug -destination 'platform=macOS' build
```

The built app lands in DerivedData (`.../Build/Products/Debug/Realm Browser.app`); launch it with `open -a <path>`.

The Podfile's `post_install` hook disables `CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER` because Realm's private headers use quoted imports that newer Xcode treats as errors — keep that hook intact when touching the Podfile.

## Testing

Tests live in the `RealmBrowserTests` target (XCTest, `RealmBrowserTests.m` with fixtures in `RLMTestObjects.h/m`):

```bash
xcodebuild -workspace RealmBrowser.xcworkspace -scheme 'Realm Browser' -destination 'platform=macOS' test
```

Run a single test with `-only-testing:RealmBrowserTests/<TestClass>/<testMethod>`.

## Legacy CI (do not trust)

`Jenkinsfile`, `.travis.yml`, and `fastlane/` date from the Xcode 8 era (HockeyApp, iTunes Connect) and do not reflect how the project is built today. Don't use them as a reference for current commands.

## Architecture

Everything is Objective-C with the `RLM` class prefix, built on Realm's Objective-C API (`@import Realm`). A shared prefix header (`RealmBrowser/Supporting Files/RealmBrowser-Prefix.pch`) is in effect.

The app follows the NSDocument architecture, with one window per open realm file:

- **Document layer** — `RLMDocument` (Models/) wraps an opened realm file and tracks its lifecycle via `RLMDocumentState` (loaded, needs encryption key, requires format upgrade, unrecoverable error). `RLMDocumentController` (Controllers/) is a custom `NSDocumentController` handling open/recents behavior; `RLMApplicationDelegate` (Application/) owns app-level concerns and the main menu.

- **Node tree model** — the sidebar and table are driven by a tree of objects conforming to the `RLMRealmOutlineNode` protocol (Models/RLMRealmOutlineNode.h). `RLMRealmNode` is the root (one per realm); `RLMTypeNode` is the base for `RLMClassNode` (an object class), `RLMArrayNode` (a list property), and `RLMResultsNode` (query results). `RLMClassProperty` wraps a schema property, and `RLMTableColumn` maps properties to table columns.

- **Navigation** — each window keeps an `RLMNavigationStack` of `RLMNavigationState` objects (with `RLMArrayNavigationState` and `RLMQueryNavigationState` subclasses) to support back/forward browsing through classes, links, and search results.

- **Window/controller layer** — `RLMRealmBrowserWindowController` is the main per-document window controller, coordinating `RLMTypeOutlineViewController` (class sidebar), `RLMInstanceTableViewController` (object table), and `RLMInspectorViewController` (property editing panel). `RLMWelcomeWindowController` provides the Xcode-style welcome/recents screen; `RLMEncryptionKeyWindowController` prompts for keys on encrypted realms.

- **Views** — `RLMTableView` plus one `...TableCellView` subclass per property type (bool, number, link, badge, image, etc.) in Views/. XIBs live in `RealmBrowser/Resources/UI/` (mostly under `Base.lproj/`).

- **Support** — `RLMModelExporter` generates model source files from a realm's schema (one of the app's stated design goals), `RLMDescriptions` formats property values for display, and `RLMTestDataGenerator`/`TestClasses` create demo realm files.

## Style

Follow the [Realm Objective-C style guide](https://github.com/realm/realm-cocoa/wiki/Objective-C-Style-Guide) and match the existing code's conventions, including the Apache-license header block at the top of each source file.
