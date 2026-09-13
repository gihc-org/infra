# TODO

## Start-prompt til ny session

Kopér blokken herunder som første besked til agenten:

> Fortsæt på **platform-laget i `infra`**. Fase 2–4 er i drift: én k3s-node
> (65.109.233.92) med ingress-nginx, cert-manager, globale security headers,
> delt TURN (`turn.gihc.online`, namespace `coturn`, ADR 0003) og testmiljøer
> for hyfer/capture/loft. Der er ikke noget akut blokerende — vælg den næste
> opgave fra listen nedenfor.
>
> Læs først `README.md`, `TODO.md`, `MIGRATION.md` og ADR'erne i `docs/adr/`
> (0001 k3s, 0002 lag-inddeling, 0003 delt TURN). Referaterne i `referater/`
> forklarer hvordan tilstanden blev nået — særligt
> `referater/2026-09-12-01-06.md` (TURN-flytningen).
>
> Åbne opgaver (i den rækkefølge jeg ville tage dem):
> 1. `capture`: færdiggør prod/beta (test kører på `capture.test.gihc.online`).
> 2. Woodpecker CI på Raspberry Pi'en (afsnittet øverst i denne fil) — fjerner
>    de manuelle `tofu apply`/Ansible-trin for alle tre repos.
> 3. Scraper på coturn-metrics (`coturn-metrics:9641`) når der kommer en
>    monitoring-stack; endpointet er verificeret, men indsamles ikke endnu.
> 4. Støtte til `ipfs-apps`' prod-deploy (`loft.gihc.online`) hvis app-siden
>    beder om det — firewall, DNS-mønster og TURN er allerede på plads.
>    App-sidens åbne punkter (bl.a. lyd-routing på telefoner) står i
>    `../ipfs-apps/TODO.md` og hører ikke til her.
>
> Kommandoer og adgang: k3s-API'et er ikke eksponeret, så SSH-tunnelen skal
> være åben — brug keepalive, den dør i stilhed efter et stykke tid:
> `ssh -o ServerAliveInterval=20 -L 6443:localhost:6443 -N -f hetzner-k3s`
> og `export KUBECONFIG=~/projects/infra/kubeconfig.yml`. Platform-laget kører
> `cd tofu && direnv allow && tofu plan` → `tofu apply` (kræver
> `HCLOUD_TOKEN`/`AWS_*` fra `pass`, som `.envrc` henter).
> Rækkefølgen ved ændringer er cloud (`main.tf`) → ansible (k3s) → platform
> (`platform.tf`). `pass` og SSH-nøgler virker via GNOME-keyring-agenten
> (`SSH_AUTH_SOCK=/run/user/1000/gcr/ssh` — den socket sandkassen ikke kan nå).
>
> Gotchas: k3s/pass/SSH og alt netværk ud af maskinen kræver eskaleret kørsel
> (sandkassen blokerer også `127.0.0.1:6443`); `tofu apply` i `platform.tf`
> fejler med TLS-timeout, hvis tunnelen er død — tjek `ss -ltn | grep 6443`
> først. `templatefile` evaluerer også kommentarer, så `${...}` i en kommentar
> vælter planen. `coturn` sætter `SO_REUSEPORT`: to instanser på noden fejler
> ikke, de deler trafikken tilfældigt. Nye DNS-records kræver
> `sudo resolvectl flush-caches` lokalt (systemd-resolved cacher negative svar
> i SOA-minimum). Læg ALDRIG hemmeligheder i git eller state — brug `pass` og
> den imperative secret-konvention i README.

## Woodpecker CI — opsætning på Raspberry Pi

Woodpecker giver automatisk deploy ved push til trunk på tværs af alle projekter
(`ipfs-apps`, `capture`, `infra`). Det fjerner det manuelle `tofu apply`- og
Ansible-trin og giver et konsistent CI-flow uden eksterne afhængigheder.

Pi'en kører Docker Compose (ikke k3s) fordi Woodpecker-agenten skal have direkte
adgang til Docker-daemonen for at køre pipeline-steps som containere. K3s ville
kræve Docker-in-Docker eller særlig runtime-konfiguration — unødvendig kompleksitet
for en dedikeret CI-maskine.

- [ ] Skriv Ansible-playbook til Pi: installér Docker, deploy `docker-compose.yml` med Woodpecker server + agent, start services
- [ ] Forbind til GitHub som forge (OAuth app i GitHub → Settings → Developer settings)
- [ ] Tilføj `HCLOUD_TOKEN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` og `ssh_private_key` som krypterede secrets i Woodpecker UI
- [ ] Skriv `.woodpecker.yaml`: `tofu plan` på PR, `tofu apply` på push til trunk

---

## Fase 2 — k3s-installation via Ansible

Ansible ejer nu k3s-installation og -opgradering (ikke kun post-provisioning):
`ansible/infra.yml` templater `/etc/rancher/k3s/config.yaml` og kører
install-scriptet, som er idempotent og kan genkøres for at opgradere.

- [x] Kør `tofu apply` (opretter bar VPS uden k3s i user_data)
- [x] Kør `ansible/infra.yml` mod VPS'en — installerer k3s og henter kubeconfig
- [x] Verificér: `kubectl get nodes`

---

## Fase 3 — Platform-lag via Helm

- [x] Installér ingress-controller (ingress-nginx)
- [x] Installér cert-manager
- [x] Opret `ClusterIssuer` mod Let's Encrypt (både staging og prod — erstatter Caddys automatiske TLS)
- [x] Verificér: curl mod en test-Ingress returnerer certifikat (`test.gihc.online`,
      production Let's Encrypt-cert, permanent sporet i `tofu/platform.tf`)

Undervejs blev k3s API'en (6443) lukket for offentlig adgang (kun tilgængelig
via SSH-tunnel) og Hetzner-backups slået til på serveren — se
`referater/2026-07-04-23-55.md`.

---

## Fase 4 — Migrer projekter

Detaljerede planer ligger i app-reposne (`../ipfs-apps/MIGRATION.md`; capture
har allerede test-miljøet kørende på k3s) samt i `MIGRATION.md` i dette repo
(tilstandsrapport 2026-08-01). Bemærk: der er ingen data at migrere — den
gamle server blev slettet før clusteret blev bygget, så migrationen er reelt
en frisk deploy.

- [x] Secrets-strategi i k8s — konvention dokumenteret i README
      ("Secrets-konvention for apps"): `pass` + imperativ `kubectl create
      secret` per miljø, intet i git
- [x] Container-image-strategi — GHCR (public packages) + GitHub Actions,
      mønster etableret via hyfer og capture
- [x] Afklar hvilke projekter der kører — `ipfs-apps`, `capture` og `hyfer`
      (sidstnævnte allerede migreret)
- [x] Globale security headers i ingress-nginx (`global-security-headers`
      ConfigMap i `tofu/platform.tf`) — CSP og Permissions-Policy per app
- [x] Firewall åbnet til coturn (TCP+UDP 3478, UDP 49152–49200) —
      forudsætning for WebRTC. Portene er ikke app-specifikke: de hører nu til
      den delte TURN-tjeneste (se afsnittet "Platform — delt TURN (coturn)")
- [ ] `capture`: færdiggør prod/beta (test kører på capture.test.gihc.online)
- [ ] `ipfs-apps`: følg `../ipfs-apps/MIGRATION.md` — beslutningerne er taget
      (statisk frontend uden IPFS, nyt domæneskema, TURN på platformen), og
      testmiljøet er i drift. Tilbage: prod-deploy af `loft.gihc.online`,
      M5-oprydning og det åbne lyd-routing-fund på telefoner (se
      `../ipfs-apps/TODO.md`)

Dynamisk volume-provisionering er allerede på plads (k3s' indbyggede
`local-path-provisioner` kører).

`docker-compose.yml` og `caddy/` er allerede fjernet fra repoet (den gamle
server de kørte på er slettet).

---

## Platform — delt TURN (coturn)

Beslutning 2026-09-11 (option B): TURN flyttes ud af `ipfs-apps` og ind i
platform-laget. Baggrunden er konkret: der er kun én node med én IP, og
`coturn` med `hostNetwork` kan kun binde 3478 én gang. Et forsøg med to
instanser viste at begge *starter* (coturn sætter `SO_REUSEPORT`), hvorefter
kernen fordeler UDP-datagrammerne mellem dem — altså tilfældige 401'ere og
timeouts i stedet for en tydelig fejl. To WebRTC-apps kan derfor ikke have
hver sin coturn på denne node.

Det erstatter beslutningen fra `referater/2026-08-01.md` ("coturn beholdes i
ipfs-apps") og følger samme mønster som [ADR 0019](../adrs/0019-shared-caddy-platform-layer.md):
når kun én proces kan binde ressourcen, flyttes den til platformen, og hver
app ejer kun sin egen konfiguration.

- [x] ADR 0003 i `docs/adr/`: delt TURN i platform-laget (erstatter
      2026-08-01-beslutningen) — `docs/adr/0003-delt-turn-platform.md`
- [x] Ejer-model afklaret: manifestet ligger i `k8s/coturn/` og læses med
      `file()`/`templatefile()` fra `tofu/platform.tf` — coturn er dermed
      OpenTofu-ejet (platform-rækken i ADR 0002), men YAML'en er en rigtig fil
- [x] Namespace `coturn` + Deployment: `hostNetwork`, pinnet image-tag + digest
      (`coturn/coturn:4.18.0`), `--denied-peer-ip` for
      RFC1918/loopback/link-local/CGNAT/IPv6, kvoter (`--max-bps`,
      `--bps-capacity`, `--user-quota`, `--total-quota`, `--stale-nonce`) og
      hærdningen fra ipfs-apps (non-root 65534, read-only rootfs, no_new_privs,
      `drop: ["ALL"]` + `add: ["NET_BIND_SERVICE"]`)
- [x] Secret i `pass` som **eneste** kilde: `turn/static-auth-secret` →
      `coturn-secret` i namespace `coturn` (imperativt, intet i git/state) og
      `scripts/turn-config.sh --config-js` til appernes `config.js`. Værdien er
      reelt offentlig (den udleveres til browseren) — beskyttelsen er kvoter +
      `--denied-peer-ip`
- [x] DNS `turn.gihc.online` → serverens IP (`scripts/create-dns-record.sh` er
      flyttet hertil og har `turn` som default; app-repoet beholder sit eget
      script til `loft.*`)
- [x] Firewall-kommentaren i `tofu/main.tf` er gjort app-uafhængig
- [x] `scripts/check-turn.sh`: STUN-binding, relay-allokering med
      HMAC-credentials og et negativt tjek (forkert secret skal afvises) — kørt
      grønt mod både den gamle app-instans og den nye platform-instans
- [x] Overvågning/metrics for coturn: `--prometheus` på 9641 + ClusterIP-
      servicen `coturn-metrics` (porten er ikke åbnet i firewall'en; der er
      endnu ingen scraper i clusteret)
- [x] Verificér at `ipfs-apps`' TURN-relay-test stadig er grøn mod den delte
      instans, efter app-manifesterne er ryddet — smoke-test 18/18 og e2e 6/6 i
      både Chromium og Firefox, inkl. relay-only TURN og et tjek af at den
      deployede sides egen `config.js` giver en relay-kandidat (2026-09-12)
- [ ] Sæt en scraper på `coturn-metrics` (Prometheus/Grafana) når der kommer
      en monitoring-stack i clusteret — metrics-endpointet er verificeret, men
      bliver ikke indsamlet endnu

Status 2026-09-12: flytningen er gennemført og verificeret — se
`referater/2026-09-12-01-06.md`. Åbne opfølgninger:

- Kvoterne er nu delte mellem apps: hæv `--total-quota` og relay-portintervallet
  når der kommer flere apps/brugere.
- Langsigtet: udsted kortlivede TURN-credentials fra appens API i stedet for at
  dele `static-auth-secret` med browseren.
- Åbent fund i `ipfs-apps` (ikke platformen): WebRTC-lyden på en telefon gik ud
  af højttaleren i stedet for Bluetooth-earpluggene. Se
  `../ipfs-apps/TODO.md` → "Lyd-routing på telefoner".

## ADR'er

- [x] ADR 0001: k3s frem for Docker Compose — `docs/adr/0001-k3s-frem-for-docker-compose.md`
- [x] ADR 0002: OpenTofu/Ansible/app-manifester lag-inddeling — `docs/adr/0002-laginddeling-tofu-ansible-apps.md`
- [x] ADR 0003: Delt TURN (coturn) som platform-tjeneste — `docs/adr/0003-delt-turn-platform.md`

Repo-lokale ADR'er i `docs/adr/` (ikke det delte ADR-repo) — beslutningerne
hører til dette projekt.
