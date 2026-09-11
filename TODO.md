# TODO

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
      forudsætning for ipfs-apps' WebRTC
- [ ] `capture`: færdiggør prod/beta (test kører på capture.test.gihc.online)
- [ ] `ipfs-apps`: følg `../ipfs-apps/MIGRATION.md` (tag beslutningerne om
      IPFS, domæneskema m.m. først)

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

- [ ] ADR 0003 i `docs/adr/`: delt TURN i platform-laget (erstatter
      2026-08-01-beslutningen)
- [ ] Ejer-model afklaret: manifestet ligger i `tofu/platform.tf` (jf. ADR
      0002's platform-række) eller i en `k8s/`-mappe i dette repo læst med
      `kubectl_file_documents`/`file()` — så coturn stadig er OpenTofu-ejet
- [ ] Namespace `coturn` + Deployment: `hostNetwork`, pinnet image-tag,
      `--denied-peer-ip` for RFC1918/loopback/link-local/CGNAT/IPv6, kvoter
      (`--max-bps`, `--bps-capacity`, `--user-quota`, `--total-quota`,
      `--stale-nonce`), og hærdningen fra ipfs-apps (non-root 65534,
      read-only rootfs, no_new_privs, `drop: ["ALL"]` +
      `add: ["NET_BIND_SERVICE"]`)
- [ ] Secret i `pass` (fx `turn/static-auth-secret`) som **eneste** kilde;
      rendres til coturns config og til hver apps `config.js` ved deploy, så
      værdien ikke kan drive mellem kopier. Værdien er reelt offentlig (den
      udleveres til browseren) — beskyttelsen er kvoter + `--denied-peer-ip`
- [ ] DNS `turn.gihc.online` → serverens IP (samme mønster som
      `scripts/create-dns-record.sh` i ipfs-apps; overvej at flytte scriptet
      hertil, nu hvor navnet er platformens)
- [ ] Firewall-kommentaren i `tofu/main.tf` gøres app-uafhængig (i dag står
      der "WebRTC relay for ipfs-apps")
- [ ] `scripts/check-turn.sh`: STUN-binding + relay-only allocation med
      HMAC-credentials, så platformen kan verificeres uden en app
- [ ] Overvågning/metrics for coturn (flyttet hertil fra ipfs-apps' TODO)
- [ ] Verificér at `ipfs-apps`' TURN-relay-test stadig er grøn mod den delte
      instans, efter app-manifesterne er ryddet

### Start-prompt til ny session

Kopér blokken herunder som første besked til agenten:

> Fortsæt på **platform-laget i `infra`**: flyt coturn (TURN) ud af
> `ipfs-apps` og ind som en delt platform-tjeneste i namespace `coturn`.
>
> Læs først `TODO.md` (afsnittet "Platform — delt TURN"), `MIGRATION.md`,
> `docs/adr/0002-laginddeling-tofu-ansible-apps.md` og
> `../adrs/0019-shared-caddy-platform-layer.md`. Baggrunden i `ipfs-apps`:
> `referater/2026-09-11-23-04.md` og `MIGRATION.md`.
>
> Beslutningen er taget (option B, 2026-09-11): TURN er platform-infrastruktur,
> ikke app-logik, og der kan kun køre én coturn på noden — to instanser binder
> begge 3478 via `SO_REUSEPORT` og deler trafikken tilfældigt.
>
> Tilstand i `ipfs-apps`: coturn kører i `loft-test` med hærdet konfiguration
> (non-root 65534, read-only rootfs, no_new_privs, `drop: ["ALL"]` +
> `add: ["NET_BIND_SERVICE"]`), `--denied-peer-ip` for private/loopback/
> link-local/CGNAT og kvoter. Relevante filer: `k8s/test/deployment-coturn.yaml`
> (args + securityContext + kommentarer om hvorfor) og
> `k8s/test/configmap.yaml` (`config.js`, `turn-secret`, `realm`,
> `external-ip`). TURN-relay-testen ligger i `e2e/tests/turn.spec.ts`.
>
> Næste skridt: skriv ADR 0003, flyt manifestet til platformen (namespace
> `coturn`), læg secret'et i `pass` som eneste kilde, opret
> `turn.gihc.online` (A-record), gør firewall-kommentaren app-uafhængig, og
> verifikér med en ny `scripts/check-turn.sh`. Derefter: sørg for at
> `ipfs-apps` peger på `turn:turn.gihc.online:3478?transport=udp` og fjerner
> sin egen coturn fra `k8s/test` og `k8s/prod`.
>
> Kommandoer og adgang: k3s-API'et er ikke eksponeret, så SSH-tunnelen skal
> være åben (`ssh -L 6443:localhost:6443 -N -f hetzner-k3s`),
> `export KUBECONFIG=~/projects/infra/kubeconfig.yml`. Platform-laget kører
> `cd tofu && direnv allow && tofu plan` → `tofu apply`. Rækkefølgen ved
> ændringer er cloud (`main.tf`) → ansible (k3s) → platform
> (`platform.tf`).
>
> Gotchas: `infra`-repoet er ikke i agentens skrive-sandkasse — spørg før
> filer ændres uden for `ipfs-apps`. `pass` og SSH-nøgler virker via
> GNOME-keyring-agenten (`SSH_AUTH_SOCK=/run/user/1000/gcr/ssh`). TURN-portene
> (TCP+UDP 3478, UDP 49152–49200) står allerede åbne i `platform-firewall`.
> ADR'er ligger repo-lokalt i `docs/adr/`.

## ADR'er

- [x] ADR 0001: k3s frem for Docker Compose — `docs/adr/0001-k3s-frem-for-docker-compose.md`
- [x] ADR 0002: OpenTofu/Ansible/app-manifester lag-inddeling — `docs/adr/0002-laginddeling-tofu-ansible-apps.md`

Repo-lokale ADR'er i `docs/adr/` (ikke det delte ADR-repo) — beslutningerne
hører til dette projekt.
