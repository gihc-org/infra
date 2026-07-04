# ── Providers (peger på k3s-clusteret) ────────────────────────────────────────

provider "helm" {
  kubernetes {
    config_path = local.kubeconfig_path
  }
}

provider "kubectl" {
  config_path = local.kubeconfig_path
}

# ── Ingress-controller ─────────────────────────────────────────────────────

# k3s' indbyggede ServiceLB (Klipper) er ikke deaktiveret (kun traefik er),
# så en almindelig Service af typen LoadBalancer bliver automatisk bundet til
# node'ens offentlige IP på port 80/443 — ingen custom values nødvendige på
# denne enkelt-node-opsætning.
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
}

# ── cert-manager ─────────────────────────────────────────────────────────────

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "crds.enabled"
    value = "true"
  }
}

# ── ClusterIssuers (Let's Encrypt) ───────────────────────────────────────────
#
# To issuers: staging til at verificere at hele kæden (Ingress → cert-manager
# → HTTP-01 → Let's Encrypt) virker uden at risikere production rate limits,
# og prod til rigtige certifikater når det er bekræftet.
#
# kubectl_manifest (i stedet for kubernetes_manifest) fordi ClusterIssuer er
# en CRD som cert-manager selv opretter i samme apply — kubernetes_manifest
# skal kende CRD-schemaet ved plan-tid, hvilket fejler her.

resource "kubectl_manifest" "letsencrypt_staging" {
  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: letsencrypt-staging
    spec:
      acme:
        server: https://acme-staging-v02.api.letsencrypt.org/directory
        email: kristian.n.jensen@gmail.com
        privateKeySecretRef:
          name: letsencrypt-staging-account-key
        solvers:
          - http01:
              ingress:
                ingressClassName: nginx
  YAML

  depends_on = [helm_release.cert_manager]
}

resource "kubectl_manifest" "letsencrypt_prod" {
  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: letsencrypt-prod
    spec:
      acme:
        server: https://acme-v02.api.letsencrypt.org/directory
        email: kristian.n.jensen@gmail.com
        privateKeySecretRef:
          name: letsencrypt-prod-account-key
        solvers:
          - http01:
              ingress:
                ingressClassName: nginx
  YAML

  depends_on = [helm_release.cert_manager]
}
