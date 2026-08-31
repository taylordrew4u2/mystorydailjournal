#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if [ ! -d "MyStoryDailyJournal.xcodeproj" ]; then
    if ! command -v xcodegen >/dev/null 2>&1; then
        echo "xcodegen is not installed. Install it with: brew install xcodegen" >&2
        exit 1
    fi

    echo "MyStoryDailyJournal.xcodeproj not found; generating it from project.yml."
    xcodegen generate
else
    echo "Using existing MyStoryDailyJournal.xcodeproj."
fi

derived_data_path="${DERIVED_DATA_PATH:-/private/tmp/MyStoryDailyJournalDerivedData}"

simulator_id=$(xcrun simctl list devices available 2>/dev/null | awk '/^[[:space:]]+iPhone/ { if (match($0, /[0-9A-Fa-f-]{36}/)) { print substr($0, RSTART, RLENGTH); exit } }')
if [ -n "$simulator_id" ]; then
    destination="id=$simulator_id"
    action="build-for-testing"
    echo "Building for testing with simulator $simulator_id."
else
    destination="generic/platform=iOS"
    action="build"
    echo "No available iPhone simulator found; compiling for generic iOS."
fi

xcodebuild "$action" \
    -project MyStoryDailyJournal.xcodeproj \
    -scheme MyStoryDailyJournal \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGN_ENTITLEMENTS=""
