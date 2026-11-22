CLUSTER := devsecops-lab
NS      := devsecops-lab
IMAGE   := gates-api:0.1.0
KYVERNO := v1.19.0
# Always target the lab cluster, never whatever context is current.
KUBECTL := kubectl --context kind-$(CLUSTER)

.PHONY: up demo scan build down

up:
	@kind get clusters | grep -qx $(CLUSTER) || kind create cluster --name $(CLUSTER)
	$(KUBECTL) apply --server-side -f https://github.com/kyverno/kyverno/releases/download/$(KYVERNO)/install.yaml
	$(KUBECTL) wait --for=condition=Available deployment --all -n kyverno --timeout=300s
	$(KUBECTL) apply -f k8s/namespace.yaml
	$(KUBECTL) apply -f k8s/policies/
	$(KUBECTL) wait --for=condition=Ready clusterpolicy --all --timeout=120s
	$(KUBECTL) apply -f k8s/security/serviceaccount.yaml -f k8s/security/secret-example.yaml

demo: build
	@echo; echo "=== 1/3 Admission: Kyverno should deny insecure-app ==="
	@if $(KUBECTL) apply -f k8s/app/insecure-app.yaml; then echo "UNEXPECTED: insecure-app was admitted"; exit 1; else echo ">>> Denied by admission, as expected"; fi
	@echo; echo "=== 2/3 Runtime: admitted, then CrashLoop (waiting 90s) ==="
	$(KUBECTL) apply -f k8s/app/admitted-but-broken.yaml
	@sleep 90
	$(KUBECTL) get pods -n $(NS) -l app=admitted-but-broken
	-$(KUBECTL) logs -n $(NS) -l app=admitted-but-broken --tail=3
	$(KUBECTL) delete -f k8s/app/admitted-but-broken.yaml
	@echo; echo "=== 3/3 Hardened app: gates-api Ready (image gate: run make scan) ==="
	kind load docker-image $(IMAGE) --name $(CLUSTER)
	$(KUBECTL) apply -f k8s/app/secure-app.yaml
	$(KUBECTL) rollout status deployment/secure-app -n $(NS) --timeout=120s
	$(KUBECTL) get pods -n $(NS) -l app=secure-app

build:
	docker build -t $(IMAGE) ./app/gates-api

scan: build
	./scripts/scan-image.sh $(IMAGE)

down:
	kind delete cluster --name $(CLUSTER)
