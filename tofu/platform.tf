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

  # Skjul nginx-versionsheaderen på alle svar (svarer til Caddys `-Server`)
  set {
    name  = "controller.config.enable-server-tokens"
    value = "false"
  }

  # Tilføj de globale security headers (ConfigMap nedenfor) på alle svar
  set {
    name  = "controller.config.add-headers"
    value = "ingress-nginx/global-security-headers"
  }
}

# Globale security headers — svarer til det platform-Caddy tidligere satte på
# hvert site. CSP og Permissions-Policy sættes bevidst IKKE globalt: CSP er
# per-app (peger på appens eget API-domæne), og Permissions-Policy adskiller
# sig pr. app (chat-frontenden skal fx kunne bruge kamera/mikrofon til WebRTC,
# mens API'erne kørte med camera=(), microphone=()).
resource "kubectl_manifest" "global_security_headers" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: global-security-headers
      namespace: ingress-nginx
    data:
      X-Content-Type-Options: "nosniff"
      X-Frame-Options: "DENY"
      Referrer-Policy: "strict-origin-when-cross-origin"
  YAML

  depends_on = [helm_release.ingress_nginx]
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

# ── Test-echo (Fase 3-verifikation, beholdt som live demo) ──────────────────
#
# Beviser at hele kæden virker: DNS → ingress-nginx → cert-manager →
# Let's Encrypt production → HTTPS. Ikke en rigtig app (det er Fase 4).

resource "kubectl_manifest" "test_echo_deployment" {
  yaml_body = <<-YAML
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: test-echo
      namespace: default
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: test-echo
      template:
        metadata:
          labels:
            app: test-echo
        spec:
          containers:
            - name: echo
              image: ealen/echo-server:latest
              ports:
                - containerPort: 80
  YAML
}

resource "kubectl_manifest" "test_echo_service" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Service
    metadata:
      name: test-echo
      namespace: default
    spec:
      selector:
        app: test-echo
      ports:
        - port: 80
          targetPort: 80
  YAML
}

resource "kubectl_manifest" "test_echo_ingress" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: test-echo
      namespace: default
      annotations:
        cert-manager.io/cluster-issuer: letsencrypt-prod
    spec:
      ingressClassName: nginx
      tls:
        - hosts:
            - test.gihc.online
          secretName: test-gihc-online-tls
      rules:
        - host: test.gihc.online
          http:
            paths:
              - path: /
                pathType: Prefix
                backend:
                  service:
                    name: test-echo
                    port:
                      number: 80
  YAML

  depends_on = [
    helm_release.ingress_nginx,
    kubectl_manifest.letsencrypt_prod,
    kubectl_manifest.test_echo_service,
  ]
}
