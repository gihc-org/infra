# infra

Platform-lag til `gihc.online`-serveren. Kører én delt Caddy-instans der betjener alle applikationer på VPS'en.

## Konceptet

Hvert projekt (`ipfs-apps`, `capture`, ...) ejer sin egen `.caddy`-konfigurationsfil i `conf.d/`. Platform-Caddy importerer dem alle:

```
conf.d/
  chat.caddy   ← skrives af ipfs-apps ansible
  notes.caddy  ← skrives af capture ansible
```

Projekterne er fuldstændigt isolerede: et projekt kan ikke ødelægge et andet projekts Caddy-konfiguration.

## Struktur

```
infra/
├── docker-compose.yml      # Caddy-service + platform_net netværk
├── caddy/
│   ├── Caddyfile           # global config: email + import conf.d/*.caddy
│   └── conf.d/             # udfyldes af de enkelte projekters ansible (gitignored)
└── ansible/
    ├── infra.yml           # engangsopsætning af VPS
    ├── inventory.yml
    └── group_vars/all/
        └── vars.yml
```

## Opsætning (første gang)

Forudsætninger:
- Ansible installeret lokalt
- SSH-nøgle til VPS: `~/.ssh/id_ed25519.hetzner`

```bash
ansible-galaxy collection install ansible.posix   # kun første gang
ansible-playbook ansible/infra.yml -i ansible/inventory.yml
```

Playbooken klarer alt: Docker-installation, mappestruktur, filsynkronisering, `platform_net`-netværket og opstart af Caddy.

## Tilføj et nyt projekt

1. Lav en `<app>.caddy.j2`-template i projektets ansible-mappe
2. Tilføj en task i projektets `deploy-test.yml`:
   ```yaml
   - name: Skriv <app>.caddy til platform conf.d
     ansible.builtin.template:
       src: templates/<app>.caddy.j2
       dest: /opt/platform/caddy/conf.d/<app>.caddy
       mode: "0644"

   - name: Genindlæs platform Caddy
     ansible.builtin.command:
       cmd: docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile
       chdir: /opt/platform
   ```
3. Sørg for at projektets containers joiner `platform_net`:
   ```yaml
   networks:
     platform_net:
       name: platform_net
       external: true
   ```

## Caddy reload vs. restart

- `caddy reload` — genindlæser config uden nedetid (brug dette normalt)
- `docker compose restart caddy` — fuld genstart (brug kun hvis reload fejler)

## VPS

| | |
|---|---|
| IP | 65.109.233.92 |
| Platform-mappe | `/opt/platform/` |
| Docker-netværk | `platform_net` |
