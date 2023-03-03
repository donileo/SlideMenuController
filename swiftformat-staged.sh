#!/bin/sh

SWIFT_FORMAT=BuildTools/.build/release/swiftformat
GIT_FORMAT_STAGED=BuildTools/git-format-staged

$GIT_FORMAT_STAGED -f "$SWIFT_FORMAT stdin --stdinpath '{}'" "*.swift"
