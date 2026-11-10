#!/bin/bash
# Startet den Cloudflare-Tunnel zu Node-RED und meldet die neue Adresse
# per MQTT an die AR-App. Die App übernimmt sie dann automatisch.
#
# Aufruf (cloudflared wird gesucht oder automatisch heruntergeladen):
#   chmod +x tunnel.sh
#   ./tunnel.sh
#
# Wichtig: Vorher Node-RED mit Passwort schützen (adminAuth in settings.js),
# denn über den Tunnel ist auch der Node-RED-Editor öffentlich erreichbar.

TOPIC="lf7/zwischenlager-emirhantlc/api"
BROKER="broker.hivemq.com"
NODE_RED="http://localhost:1880"

cd "$(dirname "$0")" || exit 1

# cloudflared suchen: im selben Ordner, systemweit oder sonst herunterladen
if [ -x ./cloudflared ]; then
  CF=./cloudflared
elif command -v cloudflared >/dev/null; then
  CF=$(command -v cloudflared)
else
  case "$(uname -m)" in
    aarch64|arm64) ARCH=arm64 ;;
    armv7l|armv6l) ARCH=arm ;;
    x86_64)        ARCH=amd64 ;;
    *) echo "Unbekannte Architektur $(uname -m), bitte cloudflared selbst installieren."; exit 1 ;;
  esac
  echo "cloudflared nicht gefunden, lade es herunter (linux-$ARCH) ..."
  curl -fL -o cloudflared "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" \
    || { echo "Download fehlgeschlagen. Internetverbindung prüfen."; rm -f cloudflared; exit 1; }
  chmod +x cloudflared
  CF=./cloudflared
fi
echo "Verwende $CF"
if ! command -v mosquitto_pub >/dev/null; then
  echo "mosquitto_pub fehlt: sudo apt install mosquitto-clients"
  exit 1
fi

echo "Starte Tunnel zu $NODE_RED ... (beenden mit Strg+C)"

"$CF" tunnel --url "$NODE_RED" 2>&1 | while IFS= read -r line; do
  echo "$line"
  url=$(echo "$line" | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | grep -v '//api\.' | head -1)
  if [ -n "$url" ]; then
    mosquitto_pub -h "$BROKER" -t "$TOPIC" -r -q 1 \
      -m "{\"url\":\"$url\",\"ts\":\"$(date -Iseconds)\"}" \
      && echo ">>> Adresse an die App gemeldet: $url" \
      || echo ">>> Melden per MQTT fehlgeschlagen. Adresse von Hand eintragen: $url"
  fi
done
