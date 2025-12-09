# ArgoCD - GitOps 지속적 배포

ArgoCD는 Kubernetes를 위한 선언적 GitOps 지속적 배포 도구입니다. Git 저장소를 신뢰할 수 있는 단일 소스(Single Source of Truth)로 사용하여 애플리케이션을 자동으로 배포하고 관리합니다.

## 목차

- [ArgoCD란?](#argocd란)
- [설치](#설치)
- [첫 번째 애플리케이션 배포](#첫-번째-애플리케이션-배포)
- [Kustomize와 통합](#kustomize와-통합)
- [고급 기능](#고급-기능)
- [Best Practices](#best-practices)
- [문제 해결](#문제-해결)

---

## ArgoCD란?

### 핵심 개념

ArgoCD는 다음 원칙을 기반으로 합니다:

```mermaid
graph LR
    A[Git Repository] -->|감지| B[ArgoCD]
    B -->|동기화| C[Kubernetes Cluster]
    C -->|상태 보고| B
    B -->|Drift 감지| D[알림]
    D -->|자동 동기화| C
```

### 주요 특징

| 특징 | 설명 |
|------|------|
| **GitOps** | Git을 배포의 신뢰할 수 있는 소스로 사용 |
| **자동 동기화** | Git 변경 사항을 자동으로 Kubernetes에 반영 |
| **Drift 감지** | 실제 상태와 선언적 상태의 차이 감지 |
| **롤백** | Git 이력을 사용한 즉각적인 롤백 |
| **Multi-cluster** | 여러 클러스터를 단일 ArgoCD로 관리 |
| **SSO 통합** | OIDC, OAuth2, SAML 2.0 지원 |

### ArgoCD vs 전통적 배포

| 항목 | 전통적 배포 | ArgoCD |
|------|------------|---------|
| 배포 방식 | Push (CI/CD가 직접 배포) | Pull (ArgoCD가 Git에서 가져옴) |
| 신뢰 소스 | CI/CD 파이프라인 | Git Repository |
| 클러스터 접근 | CI/CD에 권한 필요 | ArgoCD만 권한 필요 |
| 상태 추적 | 수동 확인 | 자동 Drift 감지 |
| 롤백 | 복잡한 절차 | Git revert만으로 가능 |

---

## 설치

### 1. ArgoCD 설치

```bash
# ArgoCD 네임스페이스 생성
kubectl create namespace argocd

# ArgoCD 설치
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 설치 확인
kubectl get pods -n argocd -w
```

예상 출력:
```
NAME                                  READY   STATUS    RESTARTS   AGE
argocd-application-controller-0       1/1     Running   0          2m
argocd-dex-server-5dd657bd9-h8pqx    1/1     Running   0          2m
argocd-redis-74cb89f466-qkmnn        1/1     Running   0          2m
argocd-repo-server-6d56c6dfb4-k5xrv  1/1     Running   0          2m
argocd-server-7d5668c5df-9zdwp       1/1     Running   0          2m
```

### 2. ArgoCD CLI 설치

```bash
# Linux
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# macOS
brew install argocd

# 버전 확인
argocd version
```

### 3. ArgoCD 서버 접근

**옵션 1: Port Forwarding (개발/테스트)**

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

브라우저에서 `https://localhost:8080` 접속

**옵션 2: LoadBalancer (프로덕션)**

```bash
# ArgoCD 서버를 LoadBalancer로 변경
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# External IP 확인
kubectl get svc argocd-server -n argocd
```

**옵션 3: Ingress (권장 - 프로덕션)**

```yaml
# argocd-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
  tls:
  - hosts:
    - argocd.example.com
    secretName: argocd-tls
```

```bash
kubectl apply -f argocd-ingress.yaml
```

### 4. 초기 패스워드 확인 및 로그인

```bash
# 초기 admin 패스워드 확인
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD Admin Password: $ARGOCD_PASSWORD"

# CLI 로그인 (Port Forward 사용 시)
argocd login localhost:8080 --username admin --password $ARGOCD_PASSWORD --insecure

# 패스워드 변경 (권장)
argocd account update-password
```

---

## 첫 번째 애플리케이션 배포

### 1. 샘플 애플리케이션 준비

Git 저장소에 다음 구조로 Kubernetes 매니페스트를 준비합니다:

```
my-app/
├── deployment.yaml
├── service.yaml
└── kustomization.yaml
```

**deployment.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: guestbook
  labels:
    app: guestbook
spec:
  replicas: 3
  selector:
    matchLabels:
      app: guestbook
  template:
    metadata:
      labels:
        app: guestbook
    spec:
      containers:
      - name: guestbook
        image: gcr.io/heptio-images/ks-guestbook-demo:0.2
        ports:
        - containerPort: 2368
          name: http
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
```

**service.yaml**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: guestbook
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 2368
    protocol: TCP
  selector:
    app: guestbook
```

### 2. ArgoCD Application 생성

**방법 1: ArgoCD CLI**

```bash
argocd app create guestbook \
  --repo https://github.com/your-org/your-repo.git \
  --path my-app \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy automated \
  --auto-prune \
  --self-heal
```

**방법 2: Kubernetes Manifest**

```yaml
# guestbook-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/your-repo.git
    targetRevision: HEAD
    path: my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
    - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

```bash
kubectl apply -f guestbook-app.yaml
```

**방법 3: ArgoCD UI**

1. ArgoCD UI 접속
2. **+ NEW APP** 클릭
3. 다음 정보 입력:
   - **Application Name**: guestbook
   - **Project**: default
   - **Sync Policy**: Automatic
   - **Repository URL**: Git 저장소 URL
   - **Path**: my-app
   - **Cluster URL**: https://kubernetes.default.svc
   - **Namespace**: default
4. **CREATE** 클릭

### 3. 동기화 확인

```bash
# Application 상태 확인
argocd app get guestbook

# 동기화 대기
argocd app wait guestbook --health

# 배포된 리소스 확인
kubectl get all -l app=guestbook
```

예상 출력:
```
Name:               guestbook
Project:            default
Server:             https://kubernetes.default.svc
Namespace:          default
URL:                https://argocd.example.com/applications/guestbook
Repo:               https://github.com/your-org/your-repo.git
Target:             HEAD
Path:               my-app
SyncWindow:         Sync Allowed
Sync Policy:        Automated (Prune)
Sync Status:        Synced to HEAD (a1b2c3d)
Health Status:      Healthy
```

### 4. 업데이트 테스트

Git 저장소에서 replicas를 변경하고 커밋합니다:

```bash
# deployment.yaml에서 replicas: 3 -> 5로 변경
git add deployment.yaml
git commit -m "Scale guestbook to 5 replicas"
git push

# ArgoCD가 자동으로 감지하고 동기화 (약 3분)
argocd app get guestbook

# 또는 수동 동기화
argocd app sync guestbook
```

---

## Kustomize와 통합

ArgoCD는 Kustomize를 네이티브로 지원합니다.

### 1. Kustomize 기반 애플리케이션 구조

```
my-app/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   └── patch-replicas.yaml
    ├── staging/
    │   ├── kustomization.yaml
    │   └── patch-replicas.yaml
    └── production/
        ├── kustomization.yaml
        ├── patch-replicas.yaml
        └── patch-resources.yaml
```

### 2. 환경별 Application 생성

**개발 환경**:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/your-repo.git
    targetRevision: HEAD
    path: my-app/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

**스테이징 환경**:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook-staging
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/your-repo.git
    targetRevision: HEAD
    path: my-app/overlays/staging
  destination:
    server: https://kubernetes.default.svc
    namespace: staging
  syncPolicy:
    automated:
      prune: false  # 스테이징은 수동 삭제
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

**프로덕션 환경**:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook-production
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/your-repo.git
    targetRevision: HEAD
    path: my-app/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: false  # 프로덕션은 수동 동기화
      selfHeal: false
    syncOptions:
    - CreateNamespace=true
```

### 3. ApplicationSet으로 다중 환경 관리

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook-multi-env
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - env: dev
        autoSync: "true"
        prune: "true"
      - env: staging
        autoSync: "true"
        prune: "true"
      - env: production
        autoSync: "false"
        prune: "false"
  template:
    metadata:
      name: 'guestbook-{{env}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/your-org/your-repo.git
        targetRevision: HEAD
        path: 'my-app/overlays/{{env}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{env}}'
      syncPolicy:
        automated:
          prune: '{{prune}}'
          selfHeal: '{{autoSync}}'
        syncOptions:
        - CreateNamespace=true
```

---

## 고급 기능

### 1. Sync Waves (배포 순서 제어)

리소스 배포 순서를 제어할 수 있습니다:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: myapp
  annotations:
    argocd.argoproj.io/sync-wave: "0"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  annotations:
    argocd.argoproj.io/sync-wave: "1"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  annotations:
    argocd.argoproj.io/sync-wave: "2"
---
apiVersion: v1
kind: Service
metadata:
  name: myapp
  annotations:
    argocd.argoproj.io/sync-wave: "3"
```

낮은 wave부터 순차적으로 배포됩니다 (0 → 1 → 2 → 3).

### 2. Sync Hooks (배포 라이프사이클 훅)

배포 전후에 작업을 실행할 수 있습니다:

**PreSync Hook (배포 전 데이터베이스 마이그레이션)**:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
      - name: migration
        image: myapp:latest
        command: ["./migrate.sh"]
      restartPolicy: Never
  backoffLimit: 2
```

**PostSync Hook (배포 후 smoke test)**:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: smoke-test
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
      - name: test
        image: curlimages/curl:latest
        command: 
        - sh
        - -c
        - |
          for i in {1..10}; do
            if curl -f http://myapp/health; then
              echo "Health check passed"
              exit 0
            fi
            sleep 5
          done
          echo "Health check failed"
          exit 1
      restartPolicy: Never
```

**SyncFail Hook (배포 실패 시 알림)**:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: notify-failure
  annotations:
    argocd.argoproj.io/hook: SyncFail
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
      - name: notify
        image: curlimages/curl:latest
        command:
        - sh
        - -c
        - |
          curl -X POST https://slack.com/api/chat.postMessage \
            -H "Authorization: Bearer $SLACK_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"channel":"#deployments","text":"Deployment failed!"}'
      restartPolicy: Never
```

### 3. Progressive Delivery (점진적 배포)

**Blue-Green Deployment**:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: myapp
spec:
  replicas: 5
  strategy:
    blueGreen:
      activeService: myapp-active
      previewService: myapp-preview
      autoPromotionEnabled: false
      scaleDownDelaySeconds: 30
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: myapp:v2
```

**Canary Deployment with Analysis**:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: myapp
spec:
  replicas: 10
  strategy:
    canary:
      steps:
      - setWeight: 20
      - pause: {duration: 1m}
      - setWeight: 40
      - pause: {duration: 1m}
      - setWeight: 60
      - pause: {duration: 1m}
      - setWeight: 80
      - pause: {duration: 1m}
      analysis:
        templates:
        - templateName: success-rate
        startingStep: 2
        args:
        - name: service-name
          value: myapp
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: myapp:v2
---
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
spec:
  args:
  - name: service-name
  metrics:
  - name: success-rate
    interval: 1m
    successCondition: result >= 0.95
    failureLimit: 3
    provider:
      prometheus:
        address: http://prometheus.monitoring:9090
        query: |
          sum(rate(
            http_requests_total{service="{{args.service-name}}",status=~"2.."}[1m]
          )) / 
          sum(rate(
            http_requests_total{service="{{args.service-name}}"}[1m]
          ))
```

### 4. Multi-Cluster 관리

여러 클러스터를 하나의 ArgoCD로 관리:

```bash
# 클러스터 등록
argocd cluster add prod-cluster-context --name production
argocd cluster add staging-cluster-context --name staging

# 클러스터 목록 확인
argocd cluster list
```

**클러스터별 Application**:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapp-multi-cluster
  namespace: argocd
spec:
  generators:
  - clusters:
      selector:
        matchLabels:
          environment: production
  template:
    metadata:
      name: 'myapp-{{name}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/your-org/your-repo.git
        targetRevision: HEAD
        path: my-app/overlays/production
      destination:
        server: '{{server}}'
        namespace: production
      syncPolicy:
        automated:
          prune: false
          selfHeal: false
```

---

## Best Practices

### 1. Git Repository 구조

**권장 구조 - 환경별 분리**:

```
repos/
├── apps/
│   └── myapp/
│       ├── base/
│       └── overlays/
│           ├── dev/
│           ├── staging/
│           └── production/
└── argocd/
    └── applications/
        ├── dev/
        │   └── myapp.yaml
        ├── staging/
        │   └── myapp.yaml
        └── production/
            └── myapp.yaml
```

**App of Apps 패턴**:

```yaml
# argocd/root-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/your-repo.git
    targetRevision: HEAD
    path: argocd/applications/production
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 2. Sync Policy 전략

| 환경 | Auto Sync | Self Heal | Prune | 이유 |
|------|-----------|-----------|-------|------|
| Dev | ✅ | ✅ | ✅ | 빠른 반복 개발 |
| Staging | ✅ | ✅ | ⚠️ | 테스트 편의성 |
| Production | ❌ | ❌ | ❌ | 수동 승인 필요 |

**개발 환경**:
```yaml
syncPolicy:
  automated:
    prune: true      # 삭제된 리소스 자동 제거
    selfHeal: true   # Drift 자동 수정
```

**프로덕션 환경**:
```yaml
syncPolicy:
  automated:
    prune: false     # 수동 확인 후 삭제
    selfHeal: false  # 긴급 수정 허용
  syncOptions:
  - CreateNamespace=true
```

### 3. RBAC 설정

**프로젝트별 권한 분리**:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    # Developers - dev 환경 전체 권한
    p, role:dev-team, applications, *, dev/*, allow
    p, role:dev-team, repositories, *, *, allow
    g, dev-team, role:dev-team
    
    # QA - staging 읽기 및 동기화
    p, role:qa-team, applications, get, staging/*, allow
    p, role:qa-team, applications, sync, staging/*, allow
    g, qa-team, role:qa-team
    
    # SRE - production 전체 권한
    p, role:sre-team, applications, *, production/*, allow
    p, role:sre-team, clusters, *, *, allow
    g, sre-team, role:sre-team
    
    # Read-only - 모든 환경 읽기
    p, role:readonly, applications, get, */*, allow
    g, readonly-group, role:readonly
  policy.default: role:readonly
```

### 4. 알림 설정

**Slack 통합**:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.slack: |
    token: $slack-token
  template.app-deployed: |
    message: |
      Application {{.app.metadata.name}} is now running new version.
      Sync Status: {{.app.status.sync.status}}
  trigger.on-deployed: |
    - when: app.status.operationState.phase in ['Succeeded']
      send: [app-deployed]
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
  namespace: argocd
stringData:
  slack-token: xoxb-your-slack-token
```

**Application에 알림 추가**:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  annotations:
    notifications.argoproj.io/subscribe.on-deployed.slack: deployments-channel
```

### 5. 보안 Best Practices

**Private Git Repository 접근**:

```bash
# SSH Key 등록
argocd repo add git@github.com:your-org/private-repo.git \
  --ssh-private-key-path ~/.ssh/id_rsa

# HTTPS + Token
argocd repo add https://github.com/your-org/private-repo.git \
  --username your-username \
  --password ghp_your_github_token
```

**Sealed Secrets 사용**:

```bash
# Sealed Secrets Controller 설치
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Secret을 SealedSecret으로 변환
echo -n mypassword | kubectl create secret generic mysecret \
  --dry-run=client \
  --from-file=password=/dev/stdin \
  -o yaml | \
  kubeseal -o yaml > mysealedsecret.yaml

# Git에 커밋
git add mysealedsecret.yaml
git commit -m "Add sealed secret"
git push
```

### 6. 모니터링 및 관측성

**Prometheus 메트릭 수집**:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: argocd-metrics
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-metrics
spec:
  ports:
  - name: metrics
    port: 8082
    targetPort: 8082
  selector:
    app.kubernetes.io/name: argocd-server
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argocd-metrics
  namespace: argocd
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-metrics
  endpoints:
  - port: metrics
    interval: 30s
```

**Grafana 대시보드**:

ArgoCD 공식 대시보드 ID: `14584`

```bash
# Grafana에서 Import 사용
# Dashboard ID: 14584 입력
```

### 7. 재해 복구

**ArgoCD 백업**:

```bash
# ArgoCD 설정 백업
kubectl get configmap -n argocd -o yaml > argocd-configmaps-backup.yaml
kubectl get secret -n argocd -o yaml > argocd-secrets-backup.yaml

# Applications 백업
kubectl get applications -n argocd -o yaml > argocd-applications-backup.yaml

# ApplicationSets 백업
kubectl get applicationsets -n argocd -o yaml > argocd-applicationsets-backup.yaml
```

**복구**:

```bash
# ArgoCD 재설치
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 설정 복원
kubectl apply -f argocd-configmaps-backup.yaml
kubectl apply -f argocd-secrets-backup.yaml

# Applications 복원
kubectl apply -f argocd-applications-backup.yaml
kubectl apply -f argocd-applicationsets-backup.yaml
```

### 8. 성능 최적화

**리소스 제한 설정**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argocd-server
  namespace: argocd
spec:
  template:
    spec:
      containers:
      - name: argocd-server
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: argocd-application-controller
  namespace: argocd
spec:
  template:
    spec:
      containers:
      - name: argocd-application-controller
        resources:
          requests:
            cpu: 1000m
            memory: 2Gi
          limits:
            cpu: 2000m
            memory: 4Gi
```

**대규모 환경 설정**:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  # 동시 동기화 수 증가
  application.instanceLabelKey: argocd.argoproj.io/instance
  
  # 타임아웃 증가
  timeout.reconciliation: 300s
  timeout.hard.reconciliation: 0
  
  # 대용량 애플리케이션 지원
  application.resourceTrackingMethod: annotation+label
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
  namespace: argocd
data:
  # 컨트롤러 워커 수 증가
  application.controller.status.processors: "20"
  application.controller.operation.processors: "10"
  
  # Repo server 병렬 처리
  reposerver.parallelism.limit: "10"
```

---

## 문제 해결

### 1. Application이 동기화되지 않음

**증상**: Application이 OutOfSync 상태로 유지됨

**원인 및 해결**:

```bash
# 1. Application 상태 확인
argocd app get myapp

# 2. 상세 로그 확인
argocd app logs myapp

# 3. Diff 확인
argocd app diff myapp

# 4. 수동 동기화 시도
argocd app sync myapp --force

# 5. Hard Refresh (캐시 무시)
argocd app get myapp --hard-refresh
```

### 2. Health Check 실패

**Custom Health Check 정의**:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  resource.customizations.health.argoproj.io_Rollout: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.phase ~= nil then
        if obj.status.phase == "Healthy" then
          hs.status = "Healthy"
          hs.message = obj.status.message
          return hs
        end
      end
    end
    hs.status = "Progressing"
    hs.message = "Waiting for rollout to finish"
    return hs
```

### 3. Sync 성능 문제

**Server-Side Apply 활성화**:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
spec:
  syncPolicy:
    syncOptions:
    - ServerSideApply=true
    - PrunePropagationPolicy=background
```

### 4. Repository 접근 문제

```bash
# Repository 상태 확인
argocd repo list

# Repository 테스트
argocd repo get https://github.com/your-org/your-repo.git

# SSH Key 재등록
argocd repo rm git@github.com:your-org/your-repo.git
argocd repo add git@github.com:your-org/your-repo.git \
  --ssh-private-key-path ~/.ssh/new_id_rsa
```

### 5. 자주 발생하는 오류

| 오류 | 원인 | 해결 |
|------|------|------|
| `ComparisonError` | Git repository 접근 불가 | Repository 자격 증명 확인 |
| `SyncError` | Kubernetes API 오류 | RBAC 권한 확인 |
| `HealthCheckError` | Pod 상태 불량 | Pod 로그 확인 |
| `OutOfSync` | Drift 발생 | `selfHeal` 활성화 또는 수동 동기화 |

---

## 실습 체크리스트

이 문서의 실습을 완료했다면 다음을 확인하세요:

- [ ] ArgoCD 설치 및 UI 접근
- [ ] CLI 설치 및 로그인
- [ ] 첫 번째 Application 배포
- [ ] Git 변경 사항 자동 동기화 확인
- [ ] Kustomize 기반 다중 환경 배포
- [ ] Sync Waves 및 Hooks 사용
- [ ] RBAC 설정
- [ ] 알림 설정
- [ ] 백업 및 복구 테스트

## 추가 리소스

- [ArgoCD 공식 문서](https://argo-cd.readthedocs.io/)
- [ArgoCD GitHub](https://github.com/argoproj/argo-cd)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [Argo Rollouts](https://argoproj.github.io/argo-rollouts/)
- [GitOps Working Group](https://github.com/gitops-working-group)

---

다음 섹션에서는 배포된 애플리케이션의 성능을 검증하는 **부하 테스트**를 다룹니다! 🚀
