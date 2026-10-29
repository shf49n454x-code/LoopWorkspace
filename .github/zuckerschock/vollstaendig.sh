#!/bin/bash
# Prüft, ob in der gebauten App jedes Framework seine Programmdatei hat.
# Xcode kopiert die Plugin-Frameworks parallel; manchmal fehlt danach eine Datei, obwohl der Build „SUCCEEDED“ meldet.
# Aufruf: vollstaendig.sh <Products-Ordner> [--entfernen]
# Mit --entfernen werden unvollständige Frameworks gelöscht, damit Xcode sie im nächsten Durchlauf neu kopiert.
PRODUKTE="$1"
ENTFERNEN="${2:-}"
APP=$(find "$PRODUKTE" -maxdepth 1 -name "*.app" -print0 | xargs -0 -n1 | while read -r a; do
  if /usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$a/Info.plist" 2>/dev/null | grep -qx "Loop"; then echo "$a"; fi
done | head -1)
[ -n "$APP" ] || { echo "Loop.app fehlt"; exit 1; }
fehlt=0
for f in "$APP"/Frameworks/*.framework; do
  [ -d "$f" ] || continue
  name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$f/Info.plist" 2>/dev/null || basename "$f" .framework)
  if [ ! -f "$f/$name" ]; then
    echo "Unvollständig: $(basename "$f")"
    fehlt=1
    [ "$ENTFERNEN" = "--entfernen" ] && rm -rf "$f"
  fi
done
exit $fehlt
