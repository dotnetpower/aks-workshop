# Kustomize

Kustomize는 Kubernetes 리소스를 선언적으로 관리하고 환경별(개발, 스테이징, 프로덕션) 설정을 재사용 가능하게 만드는 도구입니다. kubectl에 내장되어 있어 별도 설치 없이 사용할 수 있습니다.

## Kustomize의 필요성

### 기존 방식의 문제점

환경별로 다른 설정이 필요한 경우:
- ❌ 각 환경마다 별도의 YAML 파일 관리
- ❌ 코드 중복으로 유지보수 어려움
- ❌ 변경 사항 동기화 누락 위험
- ❌ 환경별 차이점 파악 어려움

### Kustomize의 장점

- ✅ 기본 설정을 재사용하고 환경별 차이만 오버레이
- ✅ YAML 템플릿 엔진 불필요 (순수 YAML 유지)
- ✅ kubectl에 내장되어 별도 도구 설치 불필요
- ✅ Git으로 버전 관리 용이
- ✅ 선언적이고 예측 가능한 설정 관리

## Kustomize 아키텍처

```mermaid
graph TD
    A[base/<br/>공통 리소스] --> D[kustomize build]
    B[overlays/dev/<br/>개발 환경 설정] --> D
    C[overlays/prod/<br/>프로덕션 환경 설정] --> D
    D --> E[최종 YAML 생성]
    E --> F[kubectl apply]
```

## 실습 1: 기본 구조 만들기

### 디렉토리 구조

```bash
# 프로젝트 디렉토리 생성
mkdir -p ~/kustomize-demo/{base,overlays/{dev,prod}}
cd ~/kustomize-demo

# 디렉토리 구조 확인
tree
```

**예상 구조**:
```
kustomize-demo/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   └── replica-patch.yaml
    └── prod/
        ├── kustomization.yaml
        └── replica-patch.yaml
```

### Base 리소스 생성

**1. Base Deployment 생성**:
```bash
cat <<EOF > base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  labels:
    app: myapp
spec:
  replicas: 1
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
        image: nginx:1.27
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
EOF
```

**2. Base Service 생성**:
```bash
cat <<EOF > base/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  labels:
    app: myapp
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
  selector:
    app: myapp
EOF
```

**3. Base Kustomization 생성**:
```bash
cat <<EOF > base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml

commonLabels:
  managed-by: kustomize
EOF
```

**4. Base 설정 확인**:
```bash
# Base 리소스 빌드 확인
kubectl kustomize base/
```

## 실습 2: 개발 환경 오버레이

### Dev 환경 설정

**1. Dev 환경용 패치 생성**:
```bash
cat <<EOF > overlays/dev/replica-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 2
EOF
```

**2. Dev Kustomization 생성**:
```bash
cat <<EOF > overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: dev

namePrefix: dev-

commonLabels:
  environment: dev

bases:
  - ../../base

patches:
  - replica-patch.yaml

images:
  - name: nginx
    newTag: 1.25-alpine
EOF
```

**3. Dev 환경 빌드 확인**:
```bash
# Dev 환경 리소스 확인
kubectl kustomize overlays/dev/
```

**4. Dev 환경 배포**:
```bash
# 네임스페이스 생성
kubectl create namespace dev

# Dev 환경 배포
kubectl apply -k overlays/dev/

# 확인
kubectl get all -n dev
kubectl get deployment dev-myapp -n dev -o yaml | grep -A 2 replicas
```

## 실습 3: 프로덕션 환경 오버레이

### Prod 환경 설정

**1. Prod 환경용 패치 생성**:
```bash
cat <<EOF > overlays/prod/replica-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 5
  template:
    spec:
      containers:
      - name: myapp
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
EOF
```

**2. Prod Service 패치 생성**:
```bash
cat <<EOF > overlays/prod/service-patch.yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  type: LoadBalancer
EOF
```

**3. Prod Kustomization 생성**:
```bash
cat <<EOF > overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: prod

namePrefix: prod-

commonLabels:
  environment: prod
  tier: production

bases:
  - ../../base

patches:
  - replica-patch.yaml
  - service-patch.yaml

images:
  - name: nginx
    newTag: 1.25

commonAnnotations:
  managed-by: kustomize
  environment: production
EOF
```

**4. Prod 환경 빌드 확인**:
```bash
# Prod 환경 리소스 확인
kubectl kustomize overlays/prod/
```

**5. Prod 환경 배포**:
```bash
# 네임스페이스 생성
kubectl create namespace prod

# Prod 환경 배포
kubectl apply -k overlays/prod/

# 확인
kubectl get all -n prod
kubectl get deployment prod-myapp -n prod -o yaml | grep -A 2 replicas
kubectl get svc prod-myapp -n prod
```

## 실습 4: ConfigMap 생성기

### ConfigMap Generator 사용

**1. Base에 ConfigMap 추가**:
```bash
cat <<EOF >> base/kustomization.yaml

configMapGenerator:
  - name: app-config
    literals:
      - APP_NAME=myapp
      - LOG_LEVEL=info
EOF
```

**2. Dev 환경에서 ConfigMap 오버라이드**:
```bash
cat <<EOF >> overlays/dev/kustomization.yaml

configMapGenerator:
  - name: app-config
    behavior: merge
    literals:
      - LOG_LEVEL=debug
      - ENVIRONMENT=development
EOF
```

**3. Prod 환경에서 ConfigMap 오버라이드**:
```bash
cat <<EOF >> overlays/prod/kustomization.yaml

configMapGenerator:
  - name: app-config
    behavior: merge
    literals:
      - LOG_LEVEL=warn
      - ENVIRONMENT=production
EOF
```

**4. Deployment에서 ConfigMap 사용**:
```bash
cat <<EOF > base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  labels:
    app: myapp
spec:
  replicas: 1
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
        image: nginx:1.27
        ports:
        - containerPort: 80
        envFrom:
        - configMapRef:
            name: app-config
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
EOF
```

**5. ConfigMap 확인**:
```bash
# Dev 환경 ConfigMap
kubectl kustomize overlays/dev/ | grep -A 10 "kind: ConfigMap"

# Prod 환경 ConfigMap
kubectl kustomize overlays/prod/ | grep -A 10 "kind: ConfigMap"
```

**6. 재배포**:
```bash
# Dev 환경 재배포
kubectl apply -k overlays/dev/

# Prod 환경 재배포
kubectl apply -k overlays/prod/

# ConfigMap 확인
kubectl get configmap -n dev
kubectl describe configmap -n dev | grep -A 5 Data

kubectl get configmap -n prod
kubectl describe configmap -n prod | grep -A 5 Data
```

## 실습 5: Secret 생성기

### Secret Generator 사용

**1. Secret 파일 생성**:
```bash
# Dev 환경 시크릿
cat <<EOF > overlays/dev/secret.env
DB_PASSWORD=dev-password-123
API_KEY=dev-api-key-456
EOF

# Prod 환경 시크릿
cat <<EOF > overlays/prod/secret.env
DB_PASSWORD=prod-secure-password-xyz
API_KEY=prod-api-key-abc
EOF
```

**2. Dev Kustomization에 Secret Generator 추가**:
```bash
cat <<EOF >> overlays/dev/kustomization.yaml

secretGenerator:
  - name: app-secrets
    envs:
      - secret.env
EOF
```

**3. Prod Kustomization에 Secret Generator 추가**:
```bash
cat <<EOF >> overlays/prod/kustomization.yaml

secretGenerator:
  - name: app-secrets
    envs:
      - secret.env
EOF
```

**4. Deployment에서 Secret 사용**:
```bash
# Base Deployment 수정 (envFrom 섹션에 추가)
cat <<EOF > base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  labels:
    app: myapp
spec:
  replicas: 1
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
        image: nginx:1.27
        ports:
        - containerPort: 80
        envFrom:
        - configMapRef:
            name: app-config
        - secretRef:
            name: app-secrets
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
EOF
```

**5. Secret 배포 및 확인**:
```bash
# Dev 환경 배포
kubectl apply -k overlays/dev/

# Secret 확인 (해시 접미사 자동 생성됨)
kubectl get secrets -n dev
kubectl get deployment dev-myapp -n dev -o yaml | grep -A 5 envFrom

# Prod 환경 배포
kubectl apply -k overlays/prod/

# Secret 확인
kubectl get secrets -n prod
kubectl get deployment prod-myapp -n prod -o yaml | grep -A 5 envFrom
```

**Secret 값 확인 (디코딩)**:
```bash
# Dev 환경 시크릿 확인
SECRET_NAME=$(kubectl get secrets -n dev | grep app-secrets | awk '{print $1}')
kubectl get secret $SECRET_NAME -n dev -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
echo

# Prod 환경 시크릿 확인
SECRET_NAME=$(kubectl get secrets -n prod | grep app-secrets | awk '{print $1}')
kubectl get secret $SECRET_NAME -n prod -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
echo
```

## 실습 6: JSON 6902 패치

### 복잡한 패치 적용

**1. JSON 패치 파일 생성**:
```bash
cat <<EOF > overlays/prod/add-probe.yaml
- op: add
  path: /spec/template/spec/containers/0/livenessProbe
  value:
    httpGet:
      path: /healthz
      port: 80
    initialDelaySeconds: 30
    periodSeconds: 10

- op: add
  path: /spec/template/spec/containers/0/readinessProbe
  value:
    httpGet:
      path: /ready
      port: 80
    initialDelaySeconds: 5
    periodSeconds: 5
EOF
```

**2. Prod Kustomization 수정**:
```bash
cat <<EOF > overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: prod

namePrefix: prod-

commonLabels:
  environment: prod
  tier: production

bases:
  - ../../base

patches:
  - replica-patch.yaml
  - service-patch.yaml

patchesJson6902:
  - target:
      group: apps
      version: v1
      kind: Deployment
      name: myapp
    path: add-probe.yaml

images:
  - name: nginx
    newTag: 1.25

commonAnnotations:
  managed-by: kustomize
  environment: production

configMapGenerator:
  - name: app-config
    behavior: merge
    literals:
      - LOG_LEVEL=warn
      - ENVIRONMENT=production

secretGenerator:
  - name: app-secrets
    envs:
      - secret.env
EOF
```

**3. 패치 적용 확인**:
```bash
# 빌드하여 Probe 추가 확인
kubectl kustomize overlays/prod/ | grep -A 10 "livenessProbe"

# 배포
kubectl apply -k overlays/prod/

# Probe 확인
kubectl get deployment prod-myapp -n prod -o yaml | grep -A 15 Probe
```

## 실습 7: 리소스 변환기

### 이미지와 레이블 일괄 변경

**1. 모든 환경의 이미지 태그 변경**:
```bash
# Prod 환경 이미지 태그 업데이트
cat <<EOF > overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: prod

namePrefix: prod-

commonLabels:
  environment: prod
  tier: production
  version: v2

bases:
  - ../../base

patches:
  - replica-patch.yaml
  - service-patch.yaml

patchesJson6902:
  - target:
      group: apps
      version: v1
      kind: Deployment
      name: myapp
    path: add-probe.yaml

images:
  - name: nginx
    newName: nginx
    newTag: 1.26-alpine

commonAnnotations:
  managed-by: kustomize
  environment: production
  version: "2.0"

configMapGenerator:
  - name: app-config
    behavior: merge
    literals:
      - LOG_LEVEL=warn
      - ENVIRONMENT=production
      - VERSION=2.0

secretGenerator:
  - name: app-secrets
    envs:
      - secret.env
EOF
```

**2. 변경사항 확인 및 배포**:
```bash
# 변경사항 미리보기
kubectl diff -k overlays/prod/

# 배포
kubectl apply -k overlays/prod/

# 이미지 확인
kubectl get deployment prod-myapp -n prod -o yaml | grep image:

# 레이블 확인
kubectl get deployment prod-myapp -n prod --show-labels
```

## 주요 Kustomize 기능

### 1. 네임 변환

| 필드 | 설명 | 예시 |
|------|------|------|
| `namePrefix` | 모든 리소스 이름 앞에 접두사 추가 | `dev-`, `prod-` |
| `nameSuffix` | 모든 리소스 이름 뒤에 접미사 추가 | `-v1`, `-canary` |
| `namespace` | 모든 리소스에 네임스페이스 설정 | `dev`, `prod` |

### 2. 레이블과 어노테이션

```yaml
commonLabels:
  app: myapp
  managed-by: kustomize
  
commonAnnotations:
  description: "Managed by Kustomize"
```

### 3. 패치 방식

| 패치 방식 | 용도 | 복잡도 |
|----------|------|--------|
| Strategic Merge | 간단한 필드 오버라이드 | 낮음 |
| JSON 6902 | 정밀한 수정 (추가/삭제/변경) | 높음 |
| Inline | Kustomization 파일 내 직접 정의 | 중간 |

### 4. 생성기

```yaml
# ConfigMap 생성
configMapGenerator:
  - name: config
    literals:
      - KEY=value
    files:
      - config.properties

# Secret 생성
secretGenerator:
  - name: secrets
    envs:
      - secret.env
    files:
      - tls.crt
      - tls.key
```

## 고급 패턴

### Components 사용

**1. Components 디렉토리 생성**:
```bash
mkdir -p components/monitoring
```

**2. Monitoring Component 생성**:
```bash
cat <<EOF > components/monitoring/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component

commonLabels:
  monitoring: enabled

patches:
  - target:
      kind: Deployment
    patch: |-
      - op: add
        path: /spec/template/metadata/annotations/prometheus.io~1scrape
        value: "true"
      - op: add
        path: /spec/template/metadata/annotations/prometheus.io~1port
        value: "9090"
EOF
```

**3. Prod 환경에서 Component 사용**:
```bash
cat <<EOF >> overlays/prod/kustomization.yaml

components:
  - ../../components/monitoring
EOF
```

**4. Component 적용 확인**:
```bash
kubectl kustomize overlays/prod/ | grep -A 5 annotations
```

## 검증 및 테스트

### Kustomize 빌드 검증

```bash
# 문법 검증
kubectl kustomize overlays/dev/ > /dev/null && echo "✅ Dev 설정 유효함"
kubectl kustomize overlays/prod/ > /dev/null && echo "✅ Prod 설정 유효함"

# 차이점 비교
diff <(kubectl kustomize overlays/dev/) <(kubectl kustomize overlays/prod/) | head -20

# 특정 리소스만 추출
kubectl kustomize overlays/prod/ | grep -A 20 "kind: Deployment"
```

### Dry-run 테스트

```bash
# Dry-run으로 배포 테스트
kubectl apply -k overlays/dev/ --dry-run=client

# Server-side dry-run
kubectl apply -k overlays/prod/ --dry-run=server
```

## 정리

```bash
# 모든 리소스 삭제
kubectl delete -k overlays/dev/
kubectl delete -k overlays/prod/

# 네임스페이스 삭제
kubectl delete namespace dev prod

# 작업 디렉토리 정리
cd ~
rm -rf ~/kustomize-demo
```

## 베스트 프랙티스

### 1. 디렉토리 구조

**권장 구조**:
```
project/
├── base/                          # 공통 리소스
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   └── rbac.yaml
├── overlays/                      # 환경별 설정
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── replica-patch.yaml
│   │   └── configmap-patch.yaml
│   ├── staging/
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   └── scaling-patch.yaml
│   └── prod/
│       ├── kustomization.yaml
│       ├── namespace.yaml
│       ├── scaling-patch.yaml
│       ├── hpa.yaml
│       └── network-policy.yaml
└── components/                    # 재사용 가능한 컴포넌트
    ├── monitoring/
    │   ├── kustomization.yaml
    │   ├── prometheus-annotations.yaml
    │   └── serviceMonitor.yaml
    ├── security/
    │   ├── kustomization.yaml
    │   ├── pod-security-policy.yaml
    │   └── network-policy.yaml
    └── ingress/
        ├── kustomization.yaml
        └── ingress.yaml
```

### 2. Base 리소스 설계

**원칙**:
- ✅ 모든 환경에 공통인 설정만 포함
- ✅ 환경별 차이는 Overlay에서만 정의
- ✅ 기본값은 가장 제한적이고 안전하게 설정
- ✅ 리소스별로 파일을 분리하여 관리
- ✅ 의존성이 없는 순수한 Kubernetes 매니페스트

**예시**:
```yaml
# base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# 리소스 순서 명시 (의존성 순서대로)
resources:
  - namespace.yaml
  - configmap.yaml
  - secret.yaml
  - service.yaml
  - deployment.yaml

# 모든 리소스에 공통 레이블 추가
commonLabels:
  app.kubernetes.io/managed-by: kustomize
  app.kubernetes.io/part-of: myapp

# 공통 어노테이션
commonAnnotations:
  documentation: "https://github.com/myorg/myapp"
```

### 3. Overlay 설계 패턴

**환경별 분리 전략**:

```yaml
# overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: dev

namePrefix: dev-

bases:
  - ../../base

# 개발 환경 특성
commonLabels:
  environment: dev

# 낮은 리소스 설정
patchesStrategicMerge:
  - replica-patch.yaml      # replicas: 1
  - resource-patch.yaml     # 낮은 CPU/Memory

# 개발용 이미지 태그
images:
  - name: myapp
    newTag: dev-latest

# 개발 환경 ConfigMap
configMapGenerator:
  - name: app-config
    behavior: merge
    literals:
      - LOG_LEVEL=debug
      - ENABLE_DEBUG=true
```

```yaml
# overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: prod

namePrefix: prod-

bases:
  - ../../base

# 프로덕션 환경 특성
commonLabels:
  environment: prod
  tier: production

# 프로덕션 보안 및 성능
patchesStrategicMerge:
  - replica-patch.yaml      # replicas: 5
  - resource-patch.yaml     # 높은 CPU/Memory
  - security-patch.yaml     # SecurityContext
  - probe-patch.yaml        # Liveness/Readiness

# 추가 리소스
resources:
  - hpa.yaml
  - network-policy.yaml
  - pod-disruption-budget.yaml

# 프로덕션 이미지 (불변 태그)
images:
  - name: myapp
    newTag: v1.2.3

# 프로덕션 ConfigMap
configMapGenerator:
  - name: app-config
    behavior: merge
    literals:
      - LOG_LEVEL=warn
      - ENABLE_DEBUG=false
      - CACHE_ENABLED=true

# 모니터링 컴포넌트
components:
  - ../../components/monitoring
  - ../../components/security
```

### 4. ConfigMap/Secret 관리

**ConfigMap 패턴**:

```yaml
# base/kustomization.yaml
configMapGenerator:
  - name: app-config
    literals:
      - APP_NAME=myapp
      - APP_VERSION=1.0.0
    files:
      - configs/app.properties

# Overlay에서 병합
# overlays/prod/kustomization.yaml
configMapGenerator:
  - name: app-config
    behavior: merge  # 중요: merge 사용
    literals:
      - ENVIRONMENT=production
```

**Secret 관리 Best Practices**:

```bash
# 1. Secret 파일은 .gitignore에 추가
echo "overlays/*/secret*.yaml" >> .gitignore
echo "overlays/*/*.env" >> .gitignore

# 2. 외부 Secret 관리 도구 사용 (권장)
# - Azure Key Vault
# - HashiCorp Vault
# - Sealed Secrets
# - External Secrets Operator

# 3. Secret Generator 사용 시
cat <<EOF > overlays/prod/kustomization.yaml
secretGenerator:
  - name: app-secrets
    envs:
      - secret.env  # Git에 커밋하지 않음
    options:
      disableNameSuffixHash: false  # 해시 접미사 유지
EOF
```

### 5. 이미지 버전 관리

**태그 전략**:

```yaml
# ❌ 나쁜 예
images:
  - name: myapp
    newTag: latest  # 예측 불가능, 롤백 어려움

# ✅ 좋은 예
images:
  - name: myapp
    newTag: v1.2.3  # Semantic Versioning
  # 또는
  - name: myapp
    newTag: sha-7f2a1b9  # Git commit SHA
  # 또는
  - name: myapp
    newTag: 2024-12-09-abc123  # 날짜 + 빌드 번호
```

**이미지 레지스트리 변경**:

```yaml
images:
  - name: myapp
    newName: myregistry.azurecr.io/myapp
    newTag: v1.2.3
  # Docker Hub에서 ACR로 마이그레이션
  - name: nginx
    newName: myregistry.azurecr.io/nginx
    newTag: 1.27
```

### 6. 패치 전략

**Strategic Merge Patch (간단한 변경)**:

```yaml
# replica-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 5
  template:
    spec:
      containers:
      - name: myapp
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
```

**JSON 6902 Patch (정밀한 변경)**:

```yaml
# kustomization.yaml
patchesJson6902:
  - target:
      group: apps
      version: v1
      kind: Deployment
      name: myapp
    patch: |-
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: NEW_ENV_VAR
          value: "new-value"
      - op: replace
        path: /spec/replicas
        value: 5
```

### 7. 네임스페이스 전략

**네임스페이스 분리**:

```yaml
# overlays/dev/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dev
  labels:
    environment: dev
    istio-injection: enabled
  annotations:
    owner: "dev-team@company.com"

# overlays/dev/kustomization.yaml
resources:
  - namespace.yaml
  - ../../base

namespace: dev  # 모든 리소스에 적용
```

### 8. 검증 및 테스트

**CI/CD 파이프라인 통합**:

```bash
#!/bin/bash
# validate-kustomize.sh

set -e

ENVIRONMENTS=("dev" "staging" "prod")

for env in "${ENVIRONMENTS[@]}"; do
  echo "🔍 Validating $env environment..."
  
  # 1. Kustomize 빌드
  kubectl kustomize "overlays/$env" > "/tmp/$env-manifests.yaml"
  
  # 2. YAML 문법 검증
  yamllint "/tmp/$env-manifests.yaml"
  
  # 3. Kubernetes 스키마 검증
  kubectl apply --dry-run=server -f "/tmp/$env-manifests.yaml"
  
  # 4. 정책 검증 (OPA/Kyverno)
  conftest test "/tmp/$env-manifests.yaml"
  
  # 5. 보안 스캔
  kubesec scan "/tmp/$env-manifests.yaml"
  
  echo "✅ $env environment validated successfully"
done
```

### 9. 문서화 규칙

**kustomization.yaml 주석**:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# =============================================================================
# Production Environment Configuration
# =============================================================================
# Owner: DevOps Team
# Contact: devops@company.com
# Updated: 2024-12-09
# 
# Configuration:
# - Replicas: 5
# - Resources: High (CPU: 1000m, Memory: 1Gi)
# - Monitoring: Enabled (Prometheus)
# - Security: Pod Security Standards (Restricted)
# - High Availability: PodDisruptionBudget, Anti-Affinity
# =============================================================================

namespace: prod

resources:
  - ../../base
  - hpa.yaml
  - pdb.yaml

# ... 나머지 설정
```

### 10. 리소스 명명 규칙

**일관된 네이밍**:

```yaml
# namePrefix/nameSuffix 활용
namePrefix: myapp-
nameSuffix: -v1

# 결과:
# - Deployment: myapp-deployment-v1
# - Service: myapp-service-v1
# - ConfigMap: myapp-config-v1-<hash>
```

### 11. 버전 관리 전략

**Git 브랜치 전략**:

```bash
# 환경별 브랜치
main                    # 프로덕션
├── develop            # 개발
├── staging            # 스테이징

# 또는 환경별 디렉토리 (권장)
overlays/
├── dev/    (main 브랜치)
├── staging/ (main 브랜치)
└── prod/   (main 브랜치)
```

**GitOps 통합**:

```yaml
# ArgoCD Application
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-prod
spec:
  source:
    repoURL: https://github.com/myorg/myapp
    targetRevision: main
    path: overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 12. 성능 최적화

**빌드 최적화**:

```bash
# 큰 프로젝트의 경우 부분 빌드
kubectl kustomize overlays/prod --load-restrictor LoadRestrictionsNone

# 결과 캐싱
kustomize build overlays/prod > manifests/prod.yaml
kubectl apply -f manifests/prod.yaml
```

### 13. 보안 Best Practices

**Pod Security Standards**:

```yaml
# overlays/prod/pod-security.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: prod
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

**SecurityContext 패치**:

```yaml
# security-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: myapp
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
```

## 문제 해결

### 일반적인 오류

**1. 리소스를 찾을 수 없음**:
```bash
# bases 경로 확인
cat overlays/dev/kustomization.yaml | grep bases

# 상대 경로가 올바른지 확인
ls -la ../../base
```

**2. 패치가 적용되지 않음**:
```bash
# 패치 대상 이름 확인
kubectl kustomize overlays/prod/ | grep "name: myapp"

# namePrefix/nameSuffix 고려
```

**3. ConfigMap/Secret 해시 불일치**:
```bash
# 해시는 내용이 변경될 때마다 변경됨
# 이전 ConfigMap/Secret 삭제 후 재배포
kubectl delete configmap -n dev --all
kubectl apply -k overlays/dev/
```

### 디버깅 팁

```bash
# 상세 출력
kubectl kustomize overlays/prod/ --enable-alpha-plugins

# 특정 리소스만 확인
kubectl kustomize overlays/prod/ | yq eval 'select(.kind == "Deployment")'

# JSON 형식으로 출력
kubectl kustomize overlays/prod/ -o json | jq
```

## 추가 학습 자료

- [Kustomize 공식 문서](https://kustomize.io/)
- [Kubernetes 문서 - Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)
- [Kustomize GitHub](https://github.com/kubernetes-sigs/kustomize)

## 다음 단계

- [Blue-Green 배포](../kubernetes-basics/blue-green-deployments) - Kustomize로 배포 전략 구현
- [Canary 배포](../kubernetes-basics/canary-deployments) - 점진적 배포 자동화
- [고급 Kubernetes](../advanced-kubernetes/intro) - Helm과 Kustomize 비교
