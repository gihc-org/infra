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

## ADR'er

- [x] ADR 0001: k3s frem for Docker Compose — `docs/adr/0001-k3s-frem-for-docker-compose.md`
- [x] ADR 0002: OpenTofu/Ansible/app-manifester lag-inddeling — `docs/adr/0002-laginddeling-tofu-ansible-apps.md`

Repo-lokale ADR'er i `docs/adr/` (ikke det delte ADR-repo) — beslutningerne
hører til dette projekt.
