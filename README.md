# infra

Platform-lag til `gihc.online`-serveren. Styrer Hetzner-infrastruktur via OpenTofu
og k3s-opsætning via Ansible.

## Struktur

```
infra/
├── tofu/                   # OpenTofu — Hetzner VPS, netværk, firewall, SSH-nøgle
│   ├── versions.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
└── ansible/
    ├── infra.yml           # k3s post-provisioning (kubeconfig, verificering)
    ├── inventory.yml
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

## Ansible (k3s post-provisioning)

Ansible-playbooken køres efter `tofu apply` og sørger for at k3s er klar og
henter kubeconfig ned til din lokale maskine.

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
1. Venter på at k3s er klar (op til 5 min efter server-boot)
2. Henter kubeconfig til `kubeconfig.yml` i roden af projektet
3. Erstatter `127.0.0.1` med serverens public IP i kubeconfig
4. Verificerer at k3s kører med `kubectl get nodes`

## VPS

| | |
|---|---|
| IP | 65.109.233.92 |
| OS | Ubuntu 24.04 |
| Type | cpx22 (3 vCPU / 4 GB RAM) |
| Lokation | hel1 (Helsinki) |
