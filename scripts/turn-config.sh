#!/usr/bin/env bash
set -euo pipefail

# Printer den TURN-konfiguration en app skal bruge, med værdierne fra `pass`.
#
# Hemmeligheden findes ét sted: `pass turn/static-auth-secret` (se ADR 0003).
# Coturn får den gennem Secret'en `coturn-secret` (scripts/deploy-coturn.sh), og
# apperne får den herfra ved deploy — så de to kopier ikke kan drive fra
# hinanden.
#
# Brug:
#   ./scripts/turn-config.sh                 # miljøvariabler (source-venligt)
#   ./scripts/turn-config.sh --config-js     # de to linjer til apps' config.js
#   ./scripts/turn-config.sh --url           # kun TURN_URL
#   ./scripts/turn-config.sh --secret        # kun hemmeligheden

TURN_HOST="${TURN_HOST:-turn.gihc.online}"
TURN_PORT="${TURN_PORT:-3478}"
PASS_ENTRY="${PASS_ENTRY:-turn/static-auth-secret}"
URL="turn:${TURN_HOST}:${TURN_PORT}?transport=udp"

usage() {
    cat <<'EOF'
Printer TURN-konfigurationen for en app, med værdier fra `pass`.

Brug:
  ./scripts/turn-config.sh                 # miljøvariabler (source-venligt)
  ./scripts/turn-config.sh --config-js     # de to linjer til apps' config.js
  ./scripts/turn-config.sh --url           # kun TURN_URL
  ./scripts/turn-config.sh --secret        # kun hemmeligheden

Miljø: TURN_HOST (turn.gihc.online), TURN_PORT (3478), PASS_ENTRY
       (turn/static-auth-secret).
EOF
}

format="env"
while [ $# -gt 0 ]; do
    case "$1" in
        --config-js)    format="config-js"; shift ;;
        --url)          format="url"; shift ;;
        --secret)       format="secret"; shift ;;
        -h|--help)      usage; exit 0 ;;
        *) echo "ukendt argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ "$format" = "url" ]; then
    echo "$URL"
    exit 0
fi

if ! SECRET="$(pass "$PASS_ENTRY" 2>/dev/null)"; then
    echo "fejl: kunne ikke læse 'pass ${PASS_ENTRY}' — findes hemmeligheden?" >&2
    echo "      (oprettes af scripts/deploy-coturn.sh)" >&2
    exit 1
fi

case "$format" in
    secret)    echo "$SECRET" ;;
    env)
        echo "TURN_URL=${URL}"
        echo "TURN_SECRET=${SECRET}"
        ;;
    config-js)
        echo "const TURN_URL = '${URL}';"
        echo "const TURN_SECRET = '${SECRET}';"
        ;;
esac
