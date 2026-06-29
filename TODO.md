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

---

## Fase 1b — Remote state (forudsætning for Woodpecker + tofu i CI)

Uden delt state kan CI ikke køre `tofu apply` sikkert — state skal ligge i
Hetzner Object Storage så både din lokale maskine og Woodpecker-agenten på Pi'en
bruger samme state.

- [ ] Opret Hetzner Object Storage bucket (`gihc-tofu-state`) i hel1
- [ ] Generér S3-credentials i Hetzner Console og gem i `pass`:
  - `pass insert hetzner/s3-access-key`
  - `pass insert hetzner/s3-secret-key`
- [ ] Tilføj `AWS_ACCESS_KEY_ID` og `AWS_SECRET_ACCESS_KEY` til `tofu/.envrc`
- [ ] Opdater `tofu/versions.tf` med S3-backend (bucket-navn + endpoint)
- [ ] Kør `tofu init -migrate-state` for at flytte lokal state til bucket
- [ ] Skriv `.woodpecker.yaml`: `tofu plan` på PR, `tofu apply` på push til trunk

---

## Fase 2 — k3s-installation via Ansible

- [ ] Opdater `ansible/infra.yml`: erstat Docker-installation med k3s-installation
  - `curl -sfL https://get.k3s.io | sh` med relevant konfiguration
  - Deaktivér Traefik-standard (vi styrer ingress selv)
- [ ] Hent kubeconfig fra VPS og gem lokalt (`~/.kube/config`)
- [ ] Verificér: `kubectl get nodes`

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
- [ ] Fjern Docker Compose + Caddy fra VPS

---

## ADRs der mangler at blive skrevet

- [ ] ADR: k3s frem for Docker Compose (arkitektonisk valg med alternativer overvejet)
- [ ] ADR: OpenTofu/Ansible/Helm lag-inddeling (påvirker alle fremtidige projekter)
