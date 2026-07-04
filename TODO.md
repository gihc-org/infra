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

- [ ] Installér ingress-controller (ingress-nginx eller Traefik)
- [ ] Installér cert-manager
- [ ] Opret `ClusterIssuer` mod Let's Encrypt (erstatter Caddys automatiske TLS)
- [ ] Verificér: curl mod en test-Ingress returnerer certifikat

---

## Fase 4 — Migrer projekter

- [ ] Afklar hvilke projekter der kører (`ipfs-apps`, `capture` — flere?)
- [ ] `ipfs-apps`: opret `Namespace`, `Deployment`, `Service`, `Ingress`
- [ ] `capture`: opret `Namespace`, `Deployment`, `Service`, `Ingress`
- [ ] Verificér at eksisterende domæner virker efter migration

`docker-compose.yml` og `caddy/` er allerede fjernet fra repoet (den gamle
server de kørte på er slettet).

---

## ADRs der mangler at blive skrevet

- [ ] ADR: k3s frem for Docker Compose (arkitektonisk valg med alternativer overvejet)
- [ ] ADR: OpenTofu/Ansible/Helm lag-inddeling (påvirker alle fremtidige projekter)
