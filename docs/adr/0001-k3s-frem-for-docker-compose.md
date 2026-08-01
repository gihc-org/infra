# ADR 0001: k3s frem for Docker Compose som runtime på VPS'en

- **Status:** Accepteret (implementeret 2026-06-29 – 2026-07-05)
- **Dato:** 2026-06-29 (besluttet), 2026-07-25 (dokumenteret)

## Kontekst

Platformen kørte Docker Compose med en delt platform-Caddy som reverse proxy.
App-projekterne (`ipfs-apps`, `capture`) deployede hver deres compose-stack og
skrev en Caddy-konfigurationsfil til `/opt/platform/caddy/conf.d/` for at
registrere domæner og routes.

Svagheder i den model:

- Caddy-konfigurationen var fordelt ud over app-repos' Ansible-templates, og
  den delte Caddy-container var et fælles knek-punkt — et genindlæsning-
  problem ramte alle apps.
- TLS var implicit magi i Caddy; ACME-backoff ved nye DNS-records var en
  tilbagevendende driftsgene (se `referater/2026-05-11.md`).
- Compose-overlays pr. miljø (test/beta/prod i samme fil) var svære at
  holde konsistente, og der var ingen deklarativ model for hele platformen.
- Ønske om en mere porteføljeværdig og lærerig platform-arkitektur.

## Beslutning

k3s (lightweight, CNCF-certificeret Kubernetes) er eneste container-runtime på
VPS'en. Den indbyggede Traefik er deaktiveret; ingress håndteres af
ingress-nginx og TLS af cert-manager med Let's Encrypt (ClusterIssuers
`letsencrypt-staging` og `letsencrypt-prod`). Storage leveres af k3s'
`local-path-provisioner`. Clusteret er bevidst single-node med SQLite-
datastore — ingen HA.

Docker Compose afskaffes som runtime på VPS'en, men **beholdes som runtime på
Raspberry Pi'en til Woodpecker CI** (agenten skal have direkte adgang til
Docker-daemonen; k3s ville kræve Docker-in-Docker — se
`referater/2026-06-29-20-23.md`).

## Alternativer overvejet

- **Fortsæt Docker Compose + Caddy:** enklest, men bærer svaghederne ovenfor
  og giver ingen udvikling af platformen.
- **Fuld Kubernetes (kubeadm e.l.):** for tungt at drive og opgradere til én
  hobby-node; k3s giver samme API med minimal driftsoverhead.
- **Nomad / Docker Swarm:** mindre økosystem, dårligere dokumentation og
  community end k8s; Swarm er reelt ved vejs ende.

## Konsekvenser

- App-repos ejer deres egne k8s-manifester (`k8s/`-mapper) i stedet for
  compose-filer og Caddy-templates; infra forbliver rent platform.
- TLS er eksplicit og deklarativt (cert-manager + annotationer) i stedet for
  Caddys implicitte model; staging→prod-flowet er en bevist rutine.
- Ingen redundans: én node, Hetzner-backups (hele disken) er eneste
  sikkerhedsnet. Tilstrækkeligt til formålet.
- k3s API'en eksponeres ikke offentligt; administration sker via SSH-tunnel.
- WebSocket- og UDP-baserede tjenester (fx coturn) kan ikke ligge bag
  ingress og kræver særskilt håndtering (hostNetwork-pod + firewall-regler).
