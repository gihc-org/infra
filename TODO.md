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

Platformen kan hoste en simpel stateless app allerede nu (bevist af
test-echo-demoen i `platform.tf`), men to ting er ikke afklaret for
`ipfs-apps`/`capture` endnu:

- [ ] Secrets-strategi i k8s (i dag: `ansible-vault`-krypterede `.env`-filer
      til Docker Compose — skal erstattes af noget k8s-nativt, fx almindelige
      `Secret`-objekter oprettet via Ansible/CI, eller Sealed Secrets)
- [ ] Container-image-strategi (hvor bygges/gemmes images — Docker Hub, GHCR,
      privat registry med `imagePullSecrets`?)
- [ ] Afklar hvilke projekter der kører (`ipfs-apps`, `capture` — flere?)
- [ ] `ipfs-apps`: opret `Namespace`, `Deployment`, `Service`, `Ingress`
- [ ] `capture`: opret `Namespace`, `Deployment`, `Service`, `Ingress`
- [ ] Verificér at eksisterende domæner virker efter migration

Dynamisk volume-provisionering er allerede på plads (k3s' indbyggede
`local-path-provisioner` kører).

`docker-compose.yml` og `caddy/` er allerede fjernet fra repoet (den gamle
server de kørte på er slettet).

---

## ADRs der mangler at blive skrevet

- [ ] ADR: k3s frem for Docker Compose (arkitektonisk valg med alternativer overvejet)
- [ ] ADR: OpenTofu/Ansible/Helm lag-inddeling (påvirker alle fremtidige projekter)
