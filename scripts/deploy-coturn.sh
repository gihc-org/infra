#!/usr/bin/env bash
set -euo pipefail

# deploy-coturn.sh — deployer den delte TURN-tjeneste (ADR 0003).
#
# Rækkefølge:
#   1. Sørger for at `pass turn/static-auth-secret` findes (genererer ellers en)
#   2. `tofu apply` i tofu/ (namespace, Deployment, metrics-Service)
#   3. Opretter/opdaterer Secret'en `coturn-secret` fra pass — den er den eneste
#      kilde til HMAC-hemmeligheden og findes derfor ikke i git eller i state
#   4. Genstarter pod'en hvis hemmeligheden blev ændret, og venter på rollout
#
# Krav: åben SSH-tunnel til k3s-API'en (se README) og HCLOUD_TOKEN/AWS_*-nøgler
# i miljøet (direnv i tofu/).
#
# Brug:
#   ./scripts/deploy-coturn.sh            # plan vises, apply bekræftes
#   ./scripts/deploy-coturn.sh --yes      # uden bekræftelse

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$REPO_ROOT/kubeconfig.yml}"

NAMESPACE="coturn"
SECRET_NAME="coturn-secret"
SECRET_KEY="static-auth-secret"
PASS_ENTRY="${PASS_ENTRY:-turn/static-auth-secret}"

APPLY_ARGS=()
for arg in "$@"; do
    case "$arg" in
        -y|--yes) APPLY_ARGS+=("-auto-approve") ;;
        -h|--help)
            cat <<'EOF'
Deployer den delte TURN-tjeneste: pass-secret → tofu apply → Secret → rollout.

Brug:
  ./scripts/deploy-coturn.sh            # plan vises, apply bekræftes
  ./scripts/deploy-coturn.sh --yes      # uden bekræftelse

Miljø: KUBECONFIG (kubeconfig.yml i repo-roden), PASS_ENTRY
       (turn/static-auth-secret).
EOF
            exit 0
            ;;
        *) echo "ukendt argument: $arg" >&2; exit 2 ;;
    esac
done

if ! pass "$PASS_ENTRY" >/dev/null 2>&1; then
    echo "==> 'pass ${PASS_ENTRY}' findes ikke — genererer 32 hex-tegn (128 bit)"
    pass generate -n "$PASS_ENTRY" 32 >/dev/null
fi
TURN_SECRET="$(pass "$PASS_ENTRY")"

echo "==> tofu apply (namespace ${NAMESPACE}, Deployment, metrics-Service)"
tofu -chdir="$REPO_ROOT/tofu" apply "${APPLY_ARGS[@]}"

# Secret'en oprettes imperativt (samme konvention som app-hemmeligheder, se
# README): værdien skal hverken ligge i git eller i OpenTofu-state.
CURRENT=""
if kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" >/dev/null 2>&1; then
    CURRENT="$(kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" \
        -o jsonpath="{.data.${SECRET_KEY}}" | base64 -d)"
fi

if [ "$CURRENT" = "$TURN_SECRET" ]; then
    echo "==> Secret'en ${SECRET_NAME} er uændret"
else
    echo "==> Opretter/opdaterer Secret ${SECRET_NAME} i ${NAMESPACE} fra pass"
    kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
        --from-literal="${SECRET_KEY}=${TURN_SECRET}" \
        --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    echo "==> Genstarter coturn, så den nye hemmelighed tages i brug"
    kubectl -n "$NAMESPACE" rollout restart deployment/coturn >/dev/null
fi

echo "==> Venter på rollout"
kubectl -n "$NAMESPACE" rollout status deployment/coturn --timeout=180s
kubectl -n "$NAMESPACE" get pods -l app=coturn -o wide

echo
echo "==> Verificér udefra med: ./scripts/check-turn.sh"
echo "    (husk at hver app's config.js skal rendres på ny, hvis hemmeligheden"
echo "     blev ændret: ./scripts/turn-config.sh --config-js)"
