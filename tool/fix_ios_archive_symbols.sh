#!/bin/sh
set -eu

ARCHIVE_PATH="${1:-build/ios/archive/Runner.xcarchive}"
FRAMEWORK_NAME="objective_c.framework"
FRAMEWORK_BINARY="$ARCHIVE_PATH/Products/Applications/Runner.app/Frameworks/$FRAMEWORK_NAME/objective_c"
DSYM_OUTPUT="$ARCHIVE_PATH/dSYMs/$FRAMEWORK_NAME.dSYM"

if [ ! -d "$ARCHIVE_PATH" ]; then
  echo "Archive not found: $ARCHIVE_PATH" >&2
  exit 1
fi

if [ ! -f "$FRAMEWORK_BINARY" ]; then
  echo "Framework binary not found: $FRAMEWORK_BINARY" >&2
  exit 1
fi

rm -rf "$DSYM_OUTPUT"
/usr/bin/dsymutil "$FRAMEWORK_BINARY" -o "$DSYM_OUTPUT"

if [ ! -f "$DSYM_OUTPUT/Contents/Resources/DWARF/objective_c" ]; then
  echo "Failed to generate dSYM for $FRAMEWORK_NAME" >&2
  exit 1
fi

echo "Generated dSYM:"
echo "  $DSYM_OUTPUT"
/usr/bin/dwarfdump --uuid "$FRAMEWORK_BINARY"
/usr/bin/dwarfdump --uuid "$DSYM_OUTPUT/Contents/Resources/DWARF/objective_c"
