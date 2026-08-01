# ADR 0002: Lag-inddeling OpenTofu / Ansible / app-ejede manifester

- **Status:** Accepteret
- **Dato:** 2026-06-29 (oprindelig lag-beslutning), 2026-07-04 (præciseret:
  Ansible ejer k3s), 2026-07-25 (dokumenteret)

## Kontekst

Flere værktøjer kan dække de samme områder (OpenTofu kan provisionere både
cloud- og Kubernetes-ressourcer; Ansible kan konfigurere alt på OS-niveau;
Helm/kubectl kan installere platform-komponenter). Uden en eksplicit
ejer-model opstår overlap og udeklarativ drift.

To erfaringer undervejs formede beslutningen:

- k3s-installation i `user_data` (cloud-init) viste sig reelt udeklarativ:
  scriptet kører kun ved første boot, og `ignore_changes = [user_data]`
  maskerede al efterfølgende drift permanent (se
  `referater/2026-07-04-23-07.md`).
- Ren OpenTofu til *app*-manifester blev vurderet klodset i praksis, mens
  `hashicorp/helm`- og `alekc/kubectl`-providers viste sig velegnede til det
  fåtalige, stabile platform-lag — uden lokale helm/kubectl-binaries.

## Beslutning

| Lag | Ejer | Omfang |
|---|---|---|
| Cloud-infrastruktur | OpenTofu (`tofu/main.tf`) | VPS, privat netværk, firewall, SSH-nøgle |
| OS + k3s | Ansible (`ansible/infra.yml`) | k3s installation/opgradering via `/etc/rancher/k3s/config.yaml`, DNS-resolver, secrets-encryption |
| Platform (k8s) | OpenTofu (`tofu/platform.tf`) | ingress-nginx, cert-manager, ClusterIssuers, globale security headers |
| Apps | App-repos selv | `k8s/`-manifester (Namespace, Deployment, Service, Ingress), applies manuelt indtil CI findes |

k3s-opgradering sker ved at bump'e `k3s_version` i `group_vars` og genkøre
playbooken — `system-upgrade-controller` er fravalgt som overkill til én node.

## Alternativer overvejet

- **Alt i OpenTofu (også app-manifester):** klodset at leve med i praksis;
  `kubernetes_manifest` skal kende CRD-schemaer ved plan-tid (hønen-og-ægget
  med CRD'er installeret i samme apply), og app-deploys hører ikke hjemme i
  platform-state.
- **Helm/kubectl CLI lokalt:** endnu et par lokale værktøjer at installere og
  holde opdateret; providerne taler direkte med API'erne via Go-SDK'er.
- **k3s i cloud-init/`user_data`:** one-shot-mekanisme, kan ikke bruges til
  opgraderinger — afløst af Ansible-ejerskabet.

## Konsekvenser

- Kørselsrækkefølge ved ændringer: `tofu apply` (cloud) → `ansible-playbook`
  (k3s/kubeconfig) → `tofu apply` (platform) — sidstnævnte kræver åben
  SSH-tunnel til k3s API'en.
- Tilføjelse af en ny app kræver ingen ændring i infra-repoet.
- `alekc/kubectl`-provideren bruges bevidst frem for `hashicorp/kubernetes`
  til CRD-baserede ressourcer (ClusterIssuers), fordi den ikke skal kende
  schemaet ved plan-tid.
