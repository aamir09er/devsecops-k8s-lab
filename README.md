# Kubernetes Security Gates Lab

**Prove Kubernetes security gates — and understand what they cannot do.**

This is a local Kind lab. Clone it, apply failing YAML on purpose, and see which layer fails. GitHub Actions only validates, builds, and scans. It does **not** deploy to your cluster.

The workload we protect is **gates-api**: a tiny Go HTTP API we build. Admission-failure and CrashLoop demos still use nginx so those lessons stay reproducible without a local image.

---

## The problem

People see security YAML and assume:

```text
Kyverno installed     = the cluster is secure
CI green              = it deployed securely
Trivy findings         = a Kubernetes problem
Pod CrashLoop         = “security broke Kubernetes”
```

Those are different layers. This repo makes the difference visible.

---

## What each layer does (and does not)

| Layer | Question it answers | What it cannot do |
| --- | --- | --- |
| **Kyverno** | Will this Pod be *allowed*? | See CVEs in the image. Make nginx able to write. |
| **Runtime hardening** | How restricted is the *running* process? | Stop a vulnerable library inside the image. |
| **Trivy** | What’s in the *image we built*? | Block a privileged Pod. Deploy anything. |
| **GitHub Actions** | Does git look sane *before* you kubectl? | Talk to Kind on your laptop. |

Kyverno in this lab is an **admission floor** (four rules, `devsecops-lab` only). The secure Deployment is **stricter** than those rules (read-only root, drop `ALL`, seccomp, no SA token).

---

## Learning journey

Do this in order. You need Kind, `kubectl`, Kyverno on the cluster, Docker, and (for scanning) Trivy.

### 0. Floor, not the whole cluster

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/policies/
kubectl apply -f k8s/security/serviceaccount.yaml
kubectl apply -f k8s/security/secret-example.yaml
```

Policies match **only** `devsecops-lab`. Cluster-wide Enforce can break CoreDNS, the CNI, and Kyverno itself.

The secret is a **demo value in git**. Do not copy that pattern to production. `/ready` only reports whether the env var is set — never the value.

### 1. Admission — Kyverno rejects

```bash
kubectl apply -f k8s/app/insecure-app.yaml
```

`nginx:latest`, privileged, root, no limits.

**What you should see:** apply denied, or a Deployment that never gets Ready Pods.

### 2. Runtime — admitted, then CrashLoop

```bash
kubectl apply -f k8s/app/admitted-but-broken.yaml
kubectl get pods -n devsecops-lab
kubectl logs -n devsecops-lab -l app=admitted-but-broken
```

Passes the four policies, then `readOnlyRootFilesystem: true` with no writable volumes. nginx cannot write `/var/cache/nginx` or `/var/run`.

**What this proves:** “Kyverno allowed it” is not “the app can run.”

### 3. Build our image and run the hardened API

```bash
docker build -t gates-api:0.1.0 ./app/gates-api
kind load docker-image gates-api:0.1.0
kubectl apply -f k8s/app/secure-app.yaml
kubectl get pods -n devsecops-lab
```

`imagePullPolicy: IfNotPresent` so Kind uses the image you loaded. Non-root UID `65532` (distroless `nonroot`), drop `ALL`, read-only root (no extra volumes — this binary does not need nginx’s cache dirs), seccomp `RuntimeDefault`, `automountServiceAccountToken: false`.

```bash
kubectl port-forward -n devsecops-lab svc/gates-api 8080:8080
```

```bash
curl -s localhost:8080/
curl -s localhost:8080/health
curl -s localhost:8080/ready
```

`/ready` should look like `{"ready":true,"secret_configured":true}`. It must never include the password.

### 4. Image scan ≠ Pod hardening

A Ready Pod does not mean a clean image. Scan **the image you built**:

```bash
./scripts/scan-image.sh gates-api:0.1.0
```

The script uses `--severity HIGH,CRITICAL --exit-code 1`. Distroless OS packages may be clean while the **Go stdlib** inside the binary is not.

**What we saw in this lab (Go 1.23 builder):**

```text
debian 12 (distroless)   →  0 HIGH/CRITICAL
gates-api (gobinary)     →  21 HIGH, 1 CRITICAL  (stdlib v1.23.12)
```

Kyverno still allowed the Pod. `curl /ready` still succeeded. Trivy is a **different gate**.

**What we changed:** the builder is `golang:1.25-bookworm` (`go 1.25` in `go.mod`) so those stdlib issues can be rebuilt away. Rebuild, reload Kind, rescan:

```bash
docker build -t gates-api:0.1.0 ./app/gates-api
kind load docker-image gates-api:0.1.0
kubectl rollout restart deployment/secure-app -n devsecops-lab
./scripts/scan-image.sh gates-api:0.1.0
```

If the script still exits `1`, read the table. Remaining findings are still **yours** (Dockerfile / Go toolchain), not a Kyverno miss. The README does not claim a permanently zero CVE image.

### 5. CI ≠ deployment

Push or open a PR. GitHub Actions:

- checks manifests with kubeconform (no cluster)
- **builds** `gates-api:0.1.0` and scans it with Trivy (`exit-code: 0` so `main` is not blocked on report-only)

The **local** script is fail-closed. CI is report-only. There is no deploy step. Kind stays on your machine.

---

## Last steps (you run these)

The repo files for this lab are complete. On your machine:

1. Rebuild `gates-api:0.1.0` after the Go 1.25 bump (commands in step 4).
2. Confirm `/ready` after the restart.
3. Rescan. Note whatever Trivy still reports.
4. Commit, push, confirm Actions ran (validate + scan, **no** cluster apply).

That is the end of the lab.

---

## Repo layout

```text
app/gates-api/                  # our workload (Go 1.25 + distroless)
k8s/
  namespace.yaml
  app/
    insecure-app.yaml           # STEP 1 — admission fail (nginx)
    admitted-but-broken.yaml    # STEP 2 — Kyverno ok, nginx CrashLoop
    secure-app.yaml              # STEP 3 — gates-api + Service
  policies/
  security/
scripts/scan-image.sh           # default image: gates-api:0.1.0
.github/workflows/security.yml
```

---

## Out of scope (on purpose)

- **NetworkPolicy** — often not enforced on kindnet.
- **Image digest pinning** — `0.1.0` is better than `:latest`; it is not immutable.
- **Production secrets** — demo Secret in git is a teaching anti-pattern except as `secretKeyRef`.
- **Vault / EKS / Cosign / extra scanners / custom operators.**

Optional later, not required to finish: `scripts/posture.sh` (what running Pods have vs what Kyverno will allow next).

---

## Takeaway

```text
What I tried  →  what failed  →  why  →  what fixed it  →  what this layer still cannot protect
```

If you can explain that for Kyverno, the nginx CrashLoop, Trivy on **your** image (including a Go rebuild), `curl /ready`, and CI that does not deploy — the lab did its job.
