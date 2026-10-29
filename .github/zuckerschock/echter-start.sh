#!/bin/bash
# Startet die ad hoc signierte App normal (ohne Vorschau) und prüft, dass sie nach 10 Sekunden noch läuft.
# Aufruf: echter-start.sh <Products-Ordner> <Zielordner>
set -euo pipefail
PRODUKTE="$1"
ZIEL="$2"
mkdir -p "$ZIEL"
# Das Produkt heißt nach dem App-Namen; erkannt wird es am Programmnamen „Loop“.
APP=$(find "$PRODUKTE" -maxdepth 1 -name "*.app" -print0 | xargs -0 -n1 | while read -r a; do
  if /usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$a/Info.plist" 2>/dev/null | grep -qx "Loop"; then echo "$a"; fi
done | head -1)
if [ -z "$APP" ]; then
  echo "Loop.app nicht gefunden in $PRODUKTE"; ls "$PRODUKTE"
  echo "Loop.app nicht gefunden in $PRODUKTE" > "$ZIEL/ECHTER-START-FEHLER.txt"; exit 1
fi
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
# Neueste iOS-Laufzeit zuerst; passt das Gerät dort nicht, die nächstältere (wie screenshots.sh).
LAUFZEITEN=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
r = [x for x in json.load(sys.stdin)["runtimes"] if x.get("platform") == "iOS" and x.get("isAvailable")]
r.sort(key=lambda x: [int(p) for p in x["version"].split(".")], reverse=True)
print("\n".join(x["identifier"] for x in r))')
udid=""
for laufzeit in $LAUFZEITEN; do
  if udid=$(xcrun simctl create "ZS Echter Start" com.apple.CoreSimulator.SimDeviceType.iPhone-16 "$laufzeit" 2>/dev/null); then
    echo "Gerät: iPhone 16, $laufzeit"
    break
  fi
  udid=""
done
if [ -z "$udid" ]; then
  echo "Kein passender Simulator für das iPhone 16" | tee "$ZIEL/ECHTER-START-FEHLER.txt"; exit 1
fi
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b > /dev/null
xcrun simctl ui "$udid" appearance dark
xcrun simctl install "$udid" "$APP"
xcrun simctl launch "$udid" "$BUNDLE" -AppleLanguages "(de)" -AppleLocale de_DE > /dev/null || echo "Start meldete einen Fehler"
sleep 12
xcrun simctl io "$udid" screenshot --type=png "$ZIEL/iPhone-16-dark-echter-start.png" > /dev/null
if xcrun simctl spawn "$udid" launchctl list | grep -q "$BUNDLE"; then
  echo "Echter Start: App läuft"
else
  echo "Echter Start: App läuft nicht mehr"
  {
    echo "Die App lief 12 Sekunden nach dem normalen Start nicht mehr."
    echo
    echo "== Simulator-Log (Prozess Loop)"
    xcrun simctl spawn "$udid" log show --last 3m --style compact --predicate 'process == "Loop"' 2>/dev/null | tail -n 300
  } > "$ZIEL/ECHTER-START-FEHLER.txt"
  for bericht in "$HOME"/Library/Logs/DiagnosticReports/Loop*; do
    [ -e "$bericht" ] && cp "$bericht" "$ZIEL/" || true
  done
fi
xcrun simctl shutdown "$udid" || true
