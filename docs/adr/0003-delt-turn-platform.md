# ADR 0003: Delt TURN (coturn) som platform-tjeneste

- **Status:** Accepteret
- **Dato:** 2026-09-11 (beslutning, option B), 2026-09-12 (implementeret)

## Kontekst

Loft-frontenden i `ipfs-apps` bruger WebRTC, og de forbindelser der ikke kan
etableres direkte (symmetrisk NAT, mobilnet) skal relayes gennem TURN. I M4 blev
coturn derfor deployet som en `hostNetwork`-pod i appens eget namespace
(`loft-test`, se `referater/2026-09-11-23-04.md` i `ipfs-apps`).

Det holder ikke, når flere apps har brug for TURN. Der er én node med én
offentlig IP, og coturn kan ikke ligge bag ingress-nginx (TURN er rå TCP/UDP på
3478 plus et UDP-relay-interval, ikke HTTP). Et forsøg med to instanser viste
den værste slags fejl: begge starter, fordi coturn sætter `SO_REUSEPORT` på
socket'en, hvorefter kernen fordeler de indkomne UDP-datagrammer tilfældigt
mellem dem. Resultatet er sporadiske 401'ere og timeouts frem for en tydelig
"porten er optaget"-fejl.

Det er samme situation som i ADR 0019 (`0019-shared-caddy-platform-layer.md` i
det delte ADR-repo): når kun én proces kan binde ressourcen, er det ikke
app-logik — så hører den til platformen, og hver app ejer kun sin egen
konfiguration.

## Beslutning

TURN er en delt platform-tjeneste:

| Del | Ejer |
|---|---|
| Namespace, Deployment, metrics-Service | Platformen (`infra/k8s/coturn/` + `tofu/platform.tf`) |
| Firewall-regler (TCP+UDP 3478, UDP 49152–49200) | Platformen (`tofu/main.tf`) |
| `turn.gihc.online` (A-record) | Platformen (`scripts/create-dns-record.sh`) |
| HMAC-hemmelighed | Platformen, i `pass` som `turn/static-auth-secret` |
| TURN-URL + credentials i frontenden | Hver app (rendres fra `pass` ved deploy) |

Konkret:

- Manifestet ligger i `infra/k8s/coturn/` og applieres af OpenTofu
  (`kubectl_manifest` i `tofu/platform.tf`), så coturn er OpenTofu-ejet og
  følger platform-laget i ADR 0002. YAML-filerne ligger som rigtige filer (med
  kommentarer og historik) i stedet for inline-heredocs; kun Deployment'et
  templatets, fordi realm og `external-ip` kommer fra konfigurationen.
- Deployment'et kører `hostNetwork: true` (TURN kan ikke gå gennem
  ingress-nginx), med pinnet image-tag + digest, `Recreate`-strategi og
  hærdningen fra ipfs-apps: non-root (65534), read-only rootfs,
  `allowPrivilegeEscalation: false`, `drop: ["ALL"]` +
  `add: ["NET_BIND_SERVICE"]` (sidstnævnte er nødvendig, fordi
  `/usr/bin/turnserver` bærer file-capabilities — se gotchas i referatet
  `2026-09-11-23-04.md` i `ipfs-apps`).
- Realm er `turn.gihc.online`, og både `--external-ip` og `--relay-ip` er
  nodens offentlige IP (uden `--relay-ip` finder coturn også nodens private
  10.x-interfaces og advarer om manglende relay-adresse) — begge bundet til den
  samme konfiguration som resten af platformen.
- Misbrugsbeskyttelsen flytter med: `--denied-peer-ip` for
  RFC1918/loopback/link-local/CGNAT/IPv6 og kvoter (`--max-bps`,
  `--bps-capacity`, `--user-quota`, `--total-quota`, `--stale-nonce`).
  Secret'en er reelt offentlig (den udleveres til browseren), så kvoterne og
  peer-filtrene er modvægten — ikke hemmeligholdelse.
- Secret'en findes kun i `pass` som `turn/static-auth-secret`. Den oprettes
  imperativt som `coturn-secret` i namespace `coturn` (samme konvention som
  app-hemmeligheder, jf. README) og rendres til apps' `config.js` med
  `scripts/turn-config.sh`, så coturn og apperne ikke kan drive fra hinanden.
- Verifikation sker app-uafhængigt med `scripts/check-turn.sh`: STUN-binding,
  relay-allokering med HMAC-credentials og et negativt tjek (forkert secret
  skal afvises). Appernes egne relay-tests kører oveni mod den delte instans.
- Apps peger på `turn:turn.gihc.online:3478?transport=udp` og har ingen egne
  coturn-manifester.

## Alternativer overvejet

- **Behold coturn i ipfs-apps (beslutningen fra 2026-08-01).** Virker for én
  app, men blokerer den næste: to instanser deler trafikken tilfældigt via
  `SO_REUSEPORT` i stedet for at fejle tydeligt. Beslutningen er hermed
  erstattet.
- **Én coturn-instans per app på hver sin port.** Kræver at hver app kender sin
  egen port og at firewall og klientkonfiguration følger med; bryder TURN-URL'er
  ved omrokering og løser ikke den underliggende knaphed (én offentlig IP).
- **Egen server/IP per app.** Fuld isolation, men uforholdsmæssig
  driftskompleksitet (og pris) for at relaye medie for personlige projekter.
- **TURN bag ingress-nginx.** Umuligt: ingress-nginx taler HTTP/HTTPS, og TURN
  kræver rå TCP/UDP på 3478 plus et UDP-portinterval til relay.

## Konsekvenser

- Kvoterne er delte: `--total-quota` (40 samtidige allocations) og
  relay-portintervallet (49 porte) gælder på tværs af alle apps. Tilføjes en
  app mere, skal begge tal sandsynligvis hæves — det er en platform-ændring,
  ikke en app-ændring.
- Alle apps deler ét secret og én realm. Roterer man secret'en, skal hver apps
  `config.js` rendres igen (`scripts/turn-config.sh` gør det synligt, hvad der
  skal opdateres).
- En fejl i platform-coturn rammer alle apps samtidig. Til gengæld er der kun
  ét sted at hærde, overvåge og opdatere.
- Portene i firewall'en er allerede åbne (lagt ind 2026-08-01), og kommentaren i
  `tofu/main.tf` er gjort app-uafhængig, så platformen ikke længere refererer
  til ipfs-apps.
- Metrics: coturn eksponerer Prometheus-metrics på 9641 i `coturn`-namespace
  (`turn_total_allocations`, `turn_unauthenticated_401_requests`,
  `turn_auth_credential_failures`, `stun_binding_*` m.fl.). Der er endnu ingen
  scraper i clusteret; indtil da hentes de med `curl localhost:9641/metrics` på
  noden eller via servicen `coturn-metrics` (porten er ikke åbnet i
  firewall'en).
