# infra

Platform-lag til `gihc.online`-serveren. Styrer Hetzner-infrastruktur via OpenTofu
og k3s-opsætning via Ansible.

## Struktur

```
infra/
├── ansible.cfg             # skal ligge i repo-roden — Ansible leder kun efter config i CWD
├── tofu/                   # OpenTofu — Hetzner VPS, netværk, firewall, SSH-nøgle
│   ├── versions.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
└── ansible/
    ├── infra.yml           # k3s installation/opgradering + post-provisioning
    ├── inventory.yml
    ├── templates/
    │   └── k3s-config.yaml.j2
    └── group_vars/all/
        └── vars.yml
```

## OpenTofu (infrastruktur)

Hetzner VPS, SSH-nøgle, privat netværk og firewall styres via OpenTofu.
State gemmes i Hetzner Object Storage (`gihc-tofu-state`, hel1).

### Forudsætninger

Opret `tofu/.envrc` (gitignored) med følgende indhold — tilpas `pass`-stierne:

```bash
export HCLOUD_TOKEN=$(pass hetzner/token)
export AWS_ACCESS_KEY_ID=$(pass hetzner/object-storage/access-key)
export AWS_SECRET_ACCESS_KEY=$(pass hetzner/object-storage/secret-key)
```

Kør derefter `direnv allow` inde i `tofu/`-mappen.

### Løbende brug

```bash
cd tofu
tofu plan    # vis hvad der vil ændre sig
tofu apply   # anvend ændringer
```

### Genimport af state (ny maskine eller tom state)

Hvis state-bucketen er tom eller du skifter maskine, skal alle Hetzner-ressourcer
importeres manuelt. Kør kommandoerne i denne rækkefølge (rækkefølgen er vigtig
pga. afhængigheder). Slå netværks- og firewall-ID'er op i
[Hetzner Cloud Console](https://console.hetzner.cloud).

```bash
tofu import hcloud_ssh_key.default 111588227
tofu import hcloud_network.platform <network-id>
tofu import hcloud_network_subnet.platform <network-id>/10.0.1.0/24
tofu import hcloud_server.platform 128627926
tofu import hcloud_firewall.platform <firewall-id>
tofu import hcloud_firewall_attachment.platform <firewall-id>
```

Verificér efterfølgende at der ikke er uventede ændringer:

```bash
tofu plan    # skal vise: No changes
```

## Ansible (k3s installation og livscyklus)

Ansible ejer hele k3s-livscyklussen — installation, opgradering og konfiguration.
Tofu opretter kun den bare VPS; `user_data`/cloud-init installerer ikke k3s,
fordi det kun kører én gang ved boot og derfor ikke kan bruges til opgraderinger.

k3s-konfigurationen (`--disable traefik`, `--flannel-iface`, `--tls-san` osv.)
ligger deklarativt i `ansible/templates/k3s-config.yaml.j2`, som templates til
`/etc/rancher/k3s/config.yaml` på serveren — det er den mekanisme k3s selv
tilbyder til konfiguration, i stedet for CLI-flags gemt i et install-script.

### Forudsætninger

- Ansible installeret lokalt
- SSH-nøgle til VPS: `~/.ssh/id_ed25519.hetzner`

```bash
ansible-galaxy collection install ansible.posix   # kun første gang
```

### Kør playbook

```bash
ansible-playbook ansible/infra.yml -i ansible/inventory.yml
```

Playbooken:
1. Templater `/etc/rancher/k3s/config.yaml`
2. Installerer eller opgraderer k3s til `k3s_version` (se `group_vars/all/vars.yml`)
3. Venter på at k3s er klar (op til 5 min)
4. Henter kubeconfig til `kubeconfig.yml` i roden af projektet
5. Erstatter `127.0.0.1` med serverens public IP i kubeconfig
6. Verificerer at k3s kører med `kubectl get nodes`

### Opgrader k3s

Bump `k3s_version` i `ansible/group_vars/all/vars.yml` og kør playbooken igen.
Install-scriptet fra `get.k3s.io` er idempotent og opgraderer et eksisterende
k3s in-place.

## VPS

| | |
|---|---|
| IP | 65.109.233.92 |
| OS | Ubuntu 24.04 |
| Type | cpx22 (3 vCPU / 4 GB RAM) |
| Lokation | hel1 (Helsinki) |
