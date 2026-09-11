# coturn — delt TURN i platform-laget

Manifesterne her applieres af OpenTofu (`tofu/platform.tf`), ikke af `kubectl`
direkte. Baggrund og begrundelser: [ADR 0003](../../docs/adr/0003-delt-turn-platform.md).

| Fil | Indhold |
|---|---|
| `namespace.yaml` | namespace `coturn` |
| `deployment.yaml.tftpl` | Deployment (hostNetwork, hærdning, kvoter, `--denied-peer-ip`) |
| `service-metrics.yaml` | ClusterIP-Service til Prometheus-metrics på 9641 |

## Deploy

```bash
# 1. SSH-tunnel til k3s-API'en (se README i repo-roden)
ssh -L 6443:localhost:6443 -N -f hetzner-k3s

# 2. Secret fra pass + apply + rollout
./scripts/deploy-coturn.sh
```

Scriptet opretter `pass turn/static-auth-secret` hvis den mangler, opretter
`coturn-secret` i namespace `coturn` (den eneste kilde til HMAC-hemmeligheden),
kører `tofu apply` og genstarter pod'en hvis secret'en blev ændret.

## Verificér

```bash
./scripts/check-turn.sh        # STUN + relay-allokering + negativt tjek
```

Appernes egne relay-tests kører oveni mod den delte instans, fx
`e2e/tests/turn.spec.ts` i ipfs-apps med `TURN_URL=turn:turn.gihc.online:3478?transport=udp`.

## Opgrader image

Image'et er pinnet med både tag og digest i `tofu/variables.tf` (`coturn_image`).
Hent digest'en for et nyt tag:

```bash
curl -s 'https://hub.docker.com/v2/repositories/coturn/coturn/tags?page_size=100&ordering=last_updated' \
  | python3 -c 'import json,sys; [print(t["name"], t["digest"]) for t in json.load(sys.stdin)["results"] if t["name"]=="4.18.0"]'
```

Opdatér variablen, kør `./scripts/deploy-coturn.sh` og verificér med
`./scripts/check-turn.sh` samt appernes relay-test. Pod'en kører hostNetwork,
så en ny version er først i drift, når pod'en er genstartet (scriptet gør det).

## Apps

Hver app sætter kun sin egen `config.js`:

```js
const TURN_URL = 'turn:turn.gihc.online:3478?transport=udp';
const TURN_SECRET = '…';   // fra pass turn/static-auth-secret
```

`scripts/turn-config.sh --config-js` printer præcis de to linjer med værdien fra
`pass`, så kopien i appen ikke kan drive fra coturns.
