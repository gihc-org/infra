# Migration af `capture` og `ipfs-apps` til k3s — tilstandsrapport og forslag

Udarbejdet 2026-07-25 på baggrund af gennemgang af `../capture`, `../ipfs-apps`
og dette repo, samt live-tjek af de kørende domæner.

## Status pr. projekt

### capture

Migrationen er allerede påbegyndt i repoet:

- `k8s/`-manifester (namespace, PVC, deployment, service, ingress) findes for
  test, og `https://capture.test.gihc.online` svarer 200 med gyldigt
  Let's Encrypt-certifikat (verificeret 2026-07-25).
- GitHub Actions → GHCR-workflow (`ghcr.io/gihc-org/capture:latest`) og
  DNS-script mod Simply.com (`scripts/create-dns-record.sh`) er på plads.
- Hemmeligheder: kun `JWT_SECRET` er reelt hemmelig. Strategi er besluttet:
  i `pass`, oprettes imperativt med `kubectl create secret`, intet i git.

Mangler:

- Prod/beta-manifester og beslutning om prod/beta-domæner (nyt skema ala
  `capture.gihc.online` / `beta.capture.gihc.online`, eller genbrug af de gamle
  `*.notes.apps.gihc.online`).
- Security headers (lå i Caddy-konfigurationen, er ikke genskabt i k8s).
- Probes og resource requests/limits i deployment.
- Oprydning: `docker-compose*.yml`, `ansible/deploy*.yml`,
  `ansible/templates/notes.caddy.j2`, gamle DNS-records.
- Overvej versionerede image-tags (git SHA) i stedet for kun `:latest`.

### ipfs-apps

Intet k8s-arbejde endnu. Fire services gør det til den sværere af de to:

- `chat` (Rust/Axum) — WebSocket på `/v1/ws/:room_id`, uploads op til 50 MB,
  rate limiting keyed på `X-Forwarded-For`, in-memory presence-state
  (→ præcis 1 replica).
- `postgres` — én instans med tre databaser (`chatdb`, `chatdb_test`,
  `chatdb_beta`).
- `ipfs` (kubo) — frontend serveres via IPFS/DNSLink med Host-header-baseret
  resolution; `ipfs add` + TXT-opdatering hos Simply.com sker i deploy-flowet.
- `coturn` — TCP+UDP 3478 og UDP 49152–49200; kan ikke ligge bag ingress-nginx.

Miljøer/domæner i dag: `api.gihc.online` + `chat.apps.gihc.online` (prod),
`beta.*`, `test.*`.

## Vigtig observation: der er ingen data at migrere

Den gamle server blev slettet 2026-07-04 (clean slate, se
`referater/2026-07-04-12-00.md`), før det nye cluster blev bygget, og
Hetzner-backups blev først slået til bagefter. Live-tjek 2026-07-25 bekræfter:
`notes.apps.gihc.online`, `api.gihc.online` og `chat.apps.gihc.online` svarer
alle med ingress-nginx' standard fake-certifikat — DNS peger stadig på
serveren, men der er intet bagved.

Docker-volumenerne (SQLite-baser, postgres-data, uploads, IPFS-repo) er altså
væk, og "migration" er reelt en frisk deploy. Hvis det alligevel ikke passer,
skal datamigration (Docker-volumes → PVC) ind i planen igen.

Bonus ved samme lejlighed: da alle gamle DNS-records peger på den rigtige IP,
kan de gamle domæner genbruges direkte i Ingress uden DNS-arbejde — eller der
skiftes til det nye skema med oprydning af døde records hos Simply.com.

## Nødvendigt i infra før migration

Kun ét punkt er reelt blokerende:

1. **Firewall til coturn** (kun hvis ipfs-apps beholder WebRTC): `tofu/main.tf`
   åbner i dag kun 22/80/443. coturn kræver TCP+UDP 3478 og UDP 49152–49200 i
   `hcloud_firewall.platform`. coturn kan ikke ligge bag ingress-nginx; på
   single-node er `hostNetwork: true`-pod den simple løsning.

2. **Security headers — beslutning om placering.** Begge apps fik headers
   (nosniff, frame-deny, referrer-policy, CSP) fra Caddy. To veje:
   - Globalt: basis-headers via ingress-nginx' ConfigMap i `tofu/platform.tf`
     (ét sted, gælder alle apps). Bemærk at `configuration-snippet`-annotations
     er slået fra som standard i nyere ingress-nginx — enten ConfigMap/globalt,
     eller `allow-snippet-annotations: true` med vilje.
   - Per app som ingress-annotations (CSP er alligevel per-miljø i chat).
   Anbefaling: globale basis-headers i `platform.tf`, CSP per app.

3. **Skriv secrets-konventionen ned** — ingen ny tooling. captures mønster er
   tilstrækkeligt: hemmeligheder i `pass`, oprettet imperativt med
   `kubectl create secret`, intet i git; k3s secrets-encryption er slået til.
   Sealed Secrets kan tilføjes senere, hvis secrets skal kunne ligge i git.
   Konventionen bør dokumenteres (README eller ADR), så begge apps følger den.

Alt andet platform (ingress, cert-manager, storage, DNS-resolver-fix, backups,
secrets-encryption) er allerede på plads.

## Beslutninger der skal træffes (app-side, men blokerende)

- **ipfs-apps frontend: IPFS eller ikke.** Enten (a) behold kubo som pod + PVC
  og automatisér `ipfs add` + DNSLink-TXT i CI — komplekst, bevarer ADR-0008;
  eller (b) servér frontend som statiske filer fra et lille image pr. miljø med
  `config.js` bagt ind — matcher hyfer/capture-mønsteret, men opgiver IPFS.
- **Domæneskema** pr. app: nyt skema (`capture.test.gihc.online`-stil) eller
  genbrug af gamle domæner. Husk oprydning af døde records.
- **JWT_SECRET per miljø eller delt** — i dag delt på tværs af test/beta/prod
  i begge apps. Nemt at splitte nu, hvor secrets alligevel oprettes forfra.
- **Namespace-layout:** et namespace per miljø (fx `capture-test`, `capture`)
  med hvert sit secret/PVC. captures test bruger bare `capture` — en lille
  inkonsistens at tage stilling til.
- **postgres til ipfs-apps:** app-ejet pod + PVC (som i compose i dag, én
  instans med tre databaser). Frarådes som platform-komponent i infra.
- **Ingress-annotations per app** (app-side, ikke infra): `proxy-body-size: 50m`
  og lange WebSocket-timeouts for chat.

## Foreslået rækkefølge

1. Skriv de to manglende ADR'er (jf. `TODO.md`) — beslutningerne er friske, og
   migrationen vil underbygge dem.
2. Færdiggør capture (lille opgave): beslut prod/beta-domæner, tilføj headers +
   probes + resources, deploy, ryd op.
3. Tag beslutningerne om IPFS og coturn, tilføj firewall-reglerne her, og
   migrér ipfs-apps.
