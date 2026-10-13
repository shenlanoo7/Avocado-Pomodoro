#!/bin/bash
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")" && pwd)"
APP="${POMODORO_APP_PATH:-/Users/shenlan/Applications/Avocado Pomodoro.app}"
SCRATCH="/Users/shenlan/.hermes/cache/scratch"
TEST_DIRECTORY="$(mktemp -d "$SCRATCH/avocado-tests.XXXXXX")"
TEST_BINARY="$TEST_DIRECTORY/AvocadoTests"
trap 'rm -rf "$TEST_DIRECTORY"' EXIT
if [[ "${POMODORO_SKIP_TESTS:-0}" != 1 ]]; then
swiftc -D NATIVE_SHELL_TESTS -parse-as-library "$SOURCE/Main.swift" "$SOURCE/VisibleWindow.swift" "$SOURCE/LogStore.swift" "$SOURCE/TaskStore.swift" "$SOURCE/FirstClickTests.swift" -framework AppKit -framework WebKit -o "$TEST_BINARY"
"$TEST_BINARY"
swiftc -D NATIVE_SHELL_TESTS -parse-as-library "$SOURCE/Main.swift" "$SOURCE/VisibleWindow.swift" "$SOURCE/LogStore.swift" "$SOURCE/TaskStore.swift" "$SOURCE/LanguageTests.swift" -framework AppKit -framework WebKit -o "$TEST_BINARY"
"$TEST_BINARY"
swiftc -D NATIVE_SHELL_TESTS -parse-as-library "$SOURCE/Main.swift" "$SOURCE/VisibleWindow.swift" "$SOURCE/LogStore.swift" "$SOURCE/TaskStore.swift" "$SOURCE/LogStoreTests.swift" -framework AppKit -framework WebKit -o "$TEST_BINARY"
"$TEST_BINARY"
swiftc -parse-as-library "$SOURCE/LogStore.swift" "$SOURCE/PauseLogTests.swift" -o "$TEST_BINARY"
"$TEST_BINARY"
swiftc -parse-as-library "$SOURCE/TaskStore.swift" "$SOURCE/TaskStoreTests.swift" -o "$TEST_BINARY"
"$TEST_BINARY"
swiftc -parse-as-library "$SOURCE/VisibleWindow.swift" "$SOURCE/VisibleWindowTests.swift" -o "$TEST_BINARY"
"$TEST_BINARY"
else
    printf 'Tests skipped (POMODORO_SKIP_TESTS=1).\n'
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -parse-as-library -O "$SOURCE/Main.swift" "$SOURCE/VisibleWindow.swift" "$SOURCE/LogStore.swift" "$SOURCE/TaskStore.swift" -framework AppKit -framework WebKit -o "$APP/Contents/MacOS/AvocadoPomodoro"
cp "$SOURCE/Info.plist" "$APP/Contents/Info.plist"
# Offline rendering of the exact supplied assets. Nothing is downloaded or recolored.
command -v rsvg-convert >/dev/null || { printf 'Missing offline SVG renderer: rsvg-convert\n' >&2; exit 1; }
ICONSET="$TEST_DIRECTORY/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$SOURCE/Assets/app-icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$SOURCE/Assets/app-icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rsvg-convert --width 18 --height 18 "$SOURCE/Assets/status-icon.svg" --output "$APP/Contents/Resources/StatusIcon.png"
rsvg-convert --width 36 --height 36 "$SOURCE/Assets/status-icon.svg" --output "$APP/Contents/Resources/StatusIcon@2x.png"
cp "$SOURCE/Assets/status-icon.svg" "$APP/Contents/Resources/status-icon.svg"
cp "$SOURCE/Assets/app-icon.png" "$APP/Contents/Resources/app-icon.png"
# Three short sine beeps with an attack/release envelope; NSSound respects system volume/mute.
python3 - "$SOURCE/beep.wav" <<'PY'
import math, struct, sys, wave
rate = 44100
samples = []
for i in range(int(rate * 1.05)):
    t = i / rate
    local = t % 0.35
    gain = min(1.0, local / 0.008, max(0.0, (0.17 - local) / 0.012)) if local < 0.17 else 0.0
    samples.append(int(0.34 * gain * 32767 * math.sin(2 * math.pi * 880 * t)))
with wave.open(sys.argv[1], 'wb') as out:
    out.setnchannels(1); out.setsampwidth(2); out.setframerate(rate)
    out.writeframes(struct.pack('<' + 'h' * len(samples), *samples))
PY
cp "$SOURCE/beep.wav" "$APP/Contents/Resources/beep.wav"
MISSING=0
for FILE in index.html core.js i18n.js settings.html checklist.html; do
    if [[ -f "$SOURCE/$FILE" ]]; then
        cp "$SOURCE/$FILE" "$APP/Contents/Resources/$FILE"
    else
        printf 'WAITING: %s is not ready; rerun build.sh after frontend generation.\n' "$FILE"
        MISSING=1
    fi
done
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf 'BUILT AND INSTALLED: %s\n' "$APP"
if [[ "$MISSING" == 1 ]]; then printf 'Native binary ready; frontend incomplete. App was not launched.\n'; else printf 'Offline frontend bundled. App was not launched.\n'; fi
