#!/bin/bash
# Startet die Zuckerschock-Vorschau (Beispielwerte, ZS_VORSCHAU=1) auf mehreren Simulatoren
# und macht Screenshots. Aufruf: screenshots.sh <Products-Ordner> <Zielordner>
set -euo pipefail

PRODUKTE="$1"
ZIEL="$2"
mkdir -p "$ZIEL"

APP=$(find "$PRODUKTE" -maxdepth 1 -name "*.app" -print0 | xargs -0 -n1 | while read -r a; do
  if /usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$a/Info.plist" 2>/dev/null | grep -qx "Loop"; then echo "$a"; fi
done | head -1)
if [ -z "$APP" ]; then
  echo "Loop.app nicht gefunden in $PRODUKTE"; ls "$PRODUKTE"; exit 1
fi
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
echo "App: $APP ($BUNDLE)"

# Neueste iOS-Laufzeit zuerst; ältere als Ausweich, falls ein Gerät dort nicht mehr läuft.
LAUFZEITEN=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
r = [x for x in json.load(sys.stdin)["runtimes"] if x.get("platform") == "iOS" and x.get("isAvailable")]
r.sort(key=lambda x: [int(p) for p in x["version"].split(".")], reverse=True)
print("\n".join(x["identifier"] for x in r))')

geraet_anlegen() {
  local name="$1" typ="$2"
  for laufzeit in $LAUFZEITEN; do
    if udid=$(xcrun simctl create "ZS $name" "$typ" "$laufzeit" 2>/dev/null); then
      echo "$udid"; return 0
    fi
  done
  return 1
}

aufnehmen() {
  local udid="$1" datei="$2"; shift 2
  xcrun simctl terminate "$udid" "$BUNDLE" 2>/dev/null || true
  # Deutsch und Region Deutschland, wie auf dem iPhone (Zahlen mit Komma)
  env "$@" xcrun simctl launch "$udid" "$BUNDLE" -AppleLanguages "(de)" -AppleLocale de_DE > /dev/null
  sleep 5
  xcrun simctl io "$udid" screenshot --type=png "$ZIEL/$datei.png" > /dev/null
  echo "  $datei.png"
}

GERAETE=(
  "iPhone-SE|com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation"
  "iPhone-16|com.apple.CoreSimulator.SimDeviceType.iPhone-16"
  "iPhone-16-Pro-Max|com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max"
)

FEHLT=()
for eintrag in "${GERAETE[@]}"; do
  name="${eintrag%%|*}"; typ="${eintrag##*|}"
  if ! udid=$(geraet_anlegen "$name" "$typ"); then
    echo "Kein Simulator für $name verfügbar"; FEHLT+=("$name"); continue
  fi
  echo "== $name ($udid)"
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b > /dev/null
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
  xcrun simctl install "$udid" "$APP"

  for thema in dark light; do
    xcrun simctl ui "$udid" appearance "$thema"
    for groesse in large extra-extra-extra-large accessibility-large; do
      xcrun simctl ui "$udid" content_size "$groesse"
      aufnehmen "$udid" "$name-$thema-$groesse-heute" SIMCTL_CHILD_ZS_VORSCHAU=1
    done
    xcrun simctl ui "$udid" content_size large
  done

  # Zustände und weitere Tabs auf dem iPhone 16, Dunkel
  if [ "$name" = "iPhone-16" ]; then
    xcrun simctl ui "$udid" appearance dark
    aufnehmen "$udid" "$name-dark-large-heute-tief" SIMCTL_CHILD_ZS_VORSCHAU=1 SIMCTL_CHILD_ZS_SZENARIO=tief
    aufnehmen "$udid" "$name-dark-large-heute-alt" SIMCTL_CHILD_ZS_VORSCHAU=1 SIMCTL_CHILD_ZS_SZENARIO=alt
    aufnehmen "$udid" "$name-dark-large-heute-hoch" SIMCTL_CHILD_ZS_VORSCHAU=1 SIMCTL_CHILD_ZS_SZENARIO=hoch
    aufnehmen "$udid" "$name-dark-large-essen" SIMCTL_CHILD_ZS_VORSCHAU=1 SIMCTL_CHILD_ZS_TAB=essen
    aufnehmen "$udid" "$name-dark-large-therapie" SIMCTL_CHILD_ZS_VORSCHAU=1 SIMCTL_CHILD_ZS_TAB=therapie
    for blatt in rezept rueckblick standard manuell einstellungen; do
      aufnehmen "$udid" "$name-dark-large-essen-$blatt" SIMCTL_CHILD_ZS_VORSCHAU=1 SIMCTL_CHILD_ZS_TAB=essen SIMCTL_CHILD_ZS_ESSEN_BLATT=$blatt
    done
    aufnehmen "$udid" "$name-dark-large-vorrat" SIMCTL_CHILD_ZS_VORSCHAU=1 SIMCTL_CHILD_ZS_BLATT=vorrat
    xcrun simctl ui "$udid" appearance light
    aufnehmen "$udid" "$name-light-large-essen" SIMCTL_CHILD_ZS_VORSCHAU=1 SIMCTL_CHILD_ZS_TAB=essen
    aufnehmen "$udid" "$name-light-large-vorrat" SIMCTL_CHILD_ZS_VORSCHAU=1 SIMCTL_CHILD_ZS_BLATT=vorrat
    xcrun simctl ui "$udid" appearance dark
    xcrun simctl terminate "$udid" "$BUNDLE" || true
    # Home-Bildschirm mit App-Icon
    xcrun simctl ui "$udid" appearance light
    xcrun simctl launch "$udid" com.apple.springboard > /dev/null 2>&1 || true
    sleep 3
    xcrun simctl io "$udid" screenshot --type=png "$ZIEL/$name-homescreen-hell.png" > /dev/null
    xcrun simctl ui "$udid" appearance dark
    sleep 3
    xcrun simctl io "$udid" screenshot --type=png "$ZIEL/$name-homescreen-dunkel.png" > /dev/null
  fi

  xcrun simctl shutdown "$udid" || true
done

if [ ${#FEHLT[@]} -gt 0 ]; then
  echo "Fehlende Simulatoren: ${FEHLT[*]}" | tee "$ZIEL/FEHLT.txt"
fi
ls -1 "$ZIEL"
