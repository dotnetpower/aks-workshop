# AKS Best Practices & Security Baseline

Azure Kubernetes Service(AKS) 클러스터를 안전하고 효율적으로 운영하기 위한 종합 가이드입니다.

## 목차

- [클러스터 구성](#클러스터-구성)
- [네트워킹](#네트워킹)
- [보안](#보안)
- [모니터링 및 로깅](#모니터링-및-로깅)
- [리소스 관리](#리소스-관리)
- [고가용성](#고가용성)
- [비용 최적화](#비용-최적화)
- [운영 체크리스트](#운영-체크리스트)
- [Security Baseline](#security-baseline)
- [추가 리소스](#추가-리소스)

---

## 클러스터 구성

### 1. 클러스터 생성 Best Practices

**권장 설정**:

```bash
# 프로덕션 클러스터 생성 예시
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --location $LOCATION \
  --kubernetes-version 1.32.9 \
  --node-count 3 \
  --min-count 3 \
  --max-count 10 \
  --enable-cluster-autoscaler \
  --network-plugin azure \
  --network-policy azure \
  --load-balancer-sku standard \
  --vm-set-type VirtualMachineScaleSets \
  --node-vm-size Standard_D4s_v3 \
  --enable-managed-identity \
  --enable-azure-rbac \
  --enable-addons monitoring,azure-policy \
  --enable-aad \
  --aad-admin-group-object-ids $AAD_GROUP_ID \
  --enable-defender \
  --zones 1 2 3 \
  --tags Environment=Production Owner=DevOps
```

**핵심 옵션 설명**:

| 옵션 | 설명 | 권장 값 |
|------|------|---------|
| `--kubernetes-version` | Kubernetes 버전 | 최신 안정 버전 |
| `--enable-cluster-autoscaler` | 자동 스케일링 활성화 | ✅ 필수 |
| `--network-plugin` | 네트워크 플러그인 | `azure` (프로덕션) |
| `--network-policy` | 네트워크 정책 | `azure` 또는 `calico` |
| `--enable-managed-identity` | Managed Identity 사용 | ✅ 필수 |
| `--enable-azure-rbac` | Azure RBAC 통합 | ✅ 권장 |
| `--enable-defender` | Defender 활성화 | ✅ 권장 |
| `--zones` | 가용성 영역 | `1 2 3` (고가용성) |

### 2. Node Pool 전략

**System Node Pool (시스템 워크로드)**:

```bash
# 시스템 컴포넌트 전용 노드 풀
az aks nodepool add \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER \
  --name systempool \
  --node-count 3 \
  --node-vm-size Standard_D2s_v3 \
  --mode System \
  --node-taints CriticalAddonsOnly=true:NoSchedule \
  --zones 1 2 3
```

**User Node Pool (애플리케이션 워크로드)**:

```bash
# 애플리케이션 전용 노드 풀
az aks nodepool add \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER \
  --name apppool \
  --node-count 3 \
  --min-count 3 \
  --max-count 20 \
  --enable-cluster-autoscaler \
  --node-vm-size Standard_D4s_v3 \
  --mode User \
  --zones 1 2 3 \
  --labels workload=application tier=frontend
```

**GPU Node Pool (ML/AI 워크로드)**:

```bash
# GPU 워크로드 전용
az aks nodepool add \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER \
  --name gpupool \
  --node-count 1 \
  --min-count 0 \
  --max-count 5 \
  --enable-cluster-autoscaler \
  --node-vm-size Standard_NC6s_v3 \
  --node-taints sku=gpu:NoSchedule \
  --labels accelerator=nvidia
```

### 3. 업그레이드 전략

**자동 업그레이드 구성**:

```bash
# 자동 업그레이드 채널 설정
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --auto-upgrade-channel stable

# 유지보수 윈도우 설정
az aks maintenanceconfiguration add \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER \
  --name default \
  --weekday Saturday \
  --start-hour 2
```

**수동 업그레이드 절차**:

```bash
# 1. 사용 가능한 버전 확인
az aks get-upgrades \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER

# 2. 컨트롤 플레인 업그레이드
az aks upgrade \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --kubernetes-version 1.32.9 \
  --control-plane-only

# 3. 노드 풀 업그레이드 (하나씩)
az aks nodepool upgrade \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER \
  --name nodepool1 \
  --kubernetes-version 1.32.9
```

---

## 네트워킹

### 1. 네트워크 플러그인 선택

**Azure CNI Overlay (권장 - 프로덕션)**:

Azure CNI Overlay는 기존 Azure CNI의 IP 주소 소비 문제를 해결하면서도 성능과 보안을 유지하는 최신 네트워크 플러그인입니다.

```bash
# Azure CNI Overlay 클러스터 생성
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --location $LOCATION \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --pod-cidr 192.168.0.0/16 \
  --network-policy azure \
  --enable-managed-identity
```

**장점**:
- ✅ VNet IP 주소 절약 (Pod는 private CIDR 사용)
- ✅ Azure CNI의 모든 기능 지원 (네트워크 정책, Windows 노드 등)
- ✅ 높은 확장성 (노드당 최대 250개 Pod)
- ✅ Azure 네트워크 정책 및 Calico 지원
- ✅ Virtual Node와 호환
- ✅ VNet 피어링을 통한 직접 통신 가능

**단점**:
- ❌ 일부 레거시 Azure 서비스와 직접 통신 제한
- ❌ Pod IP가 VNet IP가 아니므로 외부 방화벽 규칙 설정 시 추가 고려 필요

**비교표**:

| 기능 | Azure CNI | Azure CNI Overlay | Kubenet |
|------|-----------|-------------------|----------|
| VNet IP 소비 | ❌ 많음 | ✅ 적음 | ✅ 적음 |
| 네트워크 정책 | ✅ Azure/Calico | ✅ Azure/Calico | ⚠️ Calico만 |
| Windows 노드 | ✅ 지원 | ✅ 지원 | ❌ 미지원 |
| Virtual Node | ✅ 지원 | ✅ 지원 | ❌ 미지원 |
| 확장성 (Pod/노드) | ⚠️ 제한적 | ✅ 최대 250 | ✅ 최대 250 |
| 성능 | ✅ 최고 | ✅ 높음 | ⚠️ 중간 |
| VNet 피어링 통신 | ✅ 직접 | ✅ 직접 | ❌ NAT 필요 |

**권장 사용 시나리오**:
- 프로덕션 환경의 대규모 클러스터
- VNet IP 주소 공간이 제한적인 환경
- Azure 네트워크 정책이 필요한 환경
- Windows 노드 또는 Virtual Node 사용 환경

**Azure CNI (기존 방식)**:

- ✅ 각 Pod가 VNet IP를 받음
- ✅ Azure 네트워크 정책 지원
- ✅ Virtual Node 지원
- ❌ IP 주소 소비가 큼
- ❌ 대규모 클러스터에서 IP 고갈 위험

**Kubenet (개발/테스트)**:

- ✅ IP 주소 절약
- ❌ 추가 라우팅 필요
- ❌ Virtual Node 미지원
- ❌ Windows 노드 미지원

### 2. Network Policy

**Azure Network Policy 예시**:

```yaml
# deny-all-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
# allow-frontend-to-backend.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
```

### 3. Ingress 컨트롤러 선택

AKS에서 사용할 수 있는 주요 Ingress 컨트롤러를 비교하고 상황에 맞는 선택 가이드를 제공합니다.

#### Nginx Ingress Controller (권장 - 범용)

**설치**:

```bash
# Helm으로 Nginx Ingress Controller 설치
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=2 \
  --set controller.nodeSelector."kubernetes\.io/os"=linux \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
  --set controller.service.externalTrafficPolicy=Local
```

**장점**:
- ✅ 오픈소스, 커뮤니티 지원 우수
- ✅ 경량, 빠른 성능
- ✅ 다양한 annotation 및 기능 지원
- ✅ 비용 효율적 (Azure Load Balancer만 사용)
- ✅ 세밀한 트래픽 제어 (rate limiting, authentication 등)
- ✅ WebSocket, gRPC 완벽 지원
- ✅ Canary 배포, A/B 테스팅 용이
- ✅ 다른 클라우드 환경으로 이식 가능

**단점**:
- ❌ WAF 기능 없음 (별도 솔루션 필요)
- ❌ Azure 네이티브 통합 부족
- ❌ SSL 인증서 관리를 직접 해야 함
- ❌ Azure Portal에서 관리 불가

**사용 예시**:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/rate-limit: "100"
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
  - hosts:
    - myapp.example.com
    secretName: myapp-tls
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
```

#### Application Gateway Ingress Controller (AGIC)

Azure Application Gateway를 Kubernetes Ingress 컨트롤러로 사용하는 Azure 네이티브 솔루션입니다.

**설치**:

```bash
# AGIC 애드온 활성화
az aks enable-addons \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --addons ingress-appgw \
  --appgw-name myApplicationGateway \
  --appgw-subnet-cidr "10.2.0.0/16"
```

**장점**:
- ✅ Azure 네이티브 통합 (Portal, Monitor, Security Center)
- ✅ WAF (Web Application Firewall) 기본 제공
- ✅ SSL 오프로딩 성능 우수
- ✅ Azure Key Vault 통합 (인증서 관리)
- ✅ Azure Private Link 지원
- ✅ Auto-scaling (트래픽에 따라 자동 확장)
- ✅ Zone-redundant (고가용성)
- ✅ End-to-end SSL 지원

**단점**:
- ❌ 비용이 높음 (Application Gateway 별도 과금)
- ❌ 설정 복잡도 높음
- ❌ Nginx 대비 기능 제한적
- ❌ 배포 시간 느림 (수분 소요)
- ❌ Annotation 지원 제한적
- ❌ 멀티 클러스터 지원 복잡

**사용 예시**:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
    appgw.ingress.kubernetes.io/ssl-redirect: "true"
    appgw.ingress.kubernetes.io/waf-policy-for-path: "/subscriptions/.../myWAFPolicy"
    appgw.ingress.kubernetes.io/backend-protocol: "https"
spec:
  tls:
  - secretName: myapp-tls
    hosts:
    - myapp.example.com
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 443
```

#### 비교표

| 기준 | Nginx Ingress | Application Gateway (AGIC) | Application Gateway for Containers (AGC) |
|------|---------------|----------------------------|------------------------------------------|
| **비용** | ✅ 낮음 (LB만) | ❌ 높음 (Gateway + LB) | ⚠️ 중간 (사용량 기반) |
| **성능** | ✅ 빠름 | ⚠️ 중간 (설정에 따라) | ✅ 빠름 (최신 아키텍처) |
| **WAF** | ❌ 없음 | ✅ 기본 제공 | ✅ 기본 제공 (WAF v2) |
| **Azure 통합** | ❌ 제한적 | ✅ 완벽 통합 | ✅ 완벽 통합 |
| **설정 복잡도** | ✅ 간단 | ❌ 복잡 | ✅ 간단 (Kubernetes 네이티브) |
| **기능 다양성** | ✅ 풍부 | ⚠️ 제한적 | ✅ 풍부 |
| **배포 속도** | ✅ 빠름 (초) | ❌ 느림 (분) | ✅ 빠름 (초~분) |
| **멀티 클라우드** | ✅ 가능 | ❌ Azure 전용 | ❌ Azure 전용 |
| **커뮤니티** | ✅ 활발 | ⚠️ 제한적 | ⚠️ 성장 중 |
| **Canary 배포** | ✅ 쉬움 | ⚠️ 복잡 | ✅ 쉬움 |
| **프로토콜 지원** | HTTP/HTTPS/gRPC | HTTP/HTTPS | HTTP/HTTPS/gRPC/TCP/TLS |
| **자동 스케일링** | Kubernetes HPA | Gateway 수준 | ✅ 자동 (트래픽 기반) |

#### Application Gateway for Containers (AGC) - 권장 (최신)

AGC는 Azure의 최신 관리형 Ingress 솔루션으로, AGIC의 단점을 개선하고 Kubernetes 네이티브한 경험을 제공합니다.

**특징**:
- ✅ Kubernetes Gateway API 표준 준수
- ✅ 빠른 배포 속도 (초~분 단위)
- ✅ 자동 스케일링 (트래픽 기반)
- ✅ WAF v2 통합
- ✅ gRPC, WebSocket, HTTP/2 완벽 지원
- ✅ TCP/TLS 프로토콜 지원
- ✅ 다중 클러스터 지원
- ✅ Azure Monitor 네이티브 통합

**설치** (ALB Controller):

```bash
# 1. ALB Controller Identity 생성
az identity create \
  --resource-group $RESOURCE_GROUP \
  --name azure-alb-identity

IDENTITY_RESOURCE_ID=$(az identity show \
  --resource-group $RESOURCE_GROUP \
  --name azure-alb-identity \
  --query id \
  --output tsv)

# 2. Kubernetes 네임스페이스 생성
kubectl create namespace alb-infra

# 3. ALB Controller 설치
az aks approuting enable \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER

# 또는 Helm으로 설치
helm install alb-controller oci://mcr.microsoft.com/application-lb/charts/alb-controller \
  --namespace alb-infra \
  --set albController.namespace=alb-infra \
  --set albController.podIdentity.identityResourceID=$IDENTITY_RESOURCE_ID
```

**ApplicationLoadBalancer 리소스 생성**:

```yaml
# application-lb.yaml
apiVersion: alb.networking.azure.io/v1
kind: ApplicationLoadBalancer
metadata:
  name: alb-demo
  namespace: alb-infra
spec:
  associations:
  - $SUBNET_ID  # AGC가 사용할 서브넷 ID
```

```bash
# 서브넷 ID 가져오기
SUBNET_ID=$(az network vnet subnet show \
  --resource-group $RESOURCE_GROUP \
  --vnet-name myVNet \
  --name alb-subnet \
  --query id \
  --output tsv)

# ApplicationLoadBalancer 배포
kubectl apply -f application-lb.yaml
```

**Gateway API 사용**:

```yaml
# gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: myapp-gateway
  namespace: default
  annotations:
    alb.networking.azure.io/alb-id: alb-demo
spec:
  gatewayClassName: azure-alb-external
  listeners:
  - name: http-listener
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: Same
  - name: https-listener
    protocol: HTTPS
    port: 443
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: myapp-tls
    allowedRoutes:
      namespaces:
        from: Same
---
# httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: myapp-route
  namespace: default
spec:
  parentRefs:
  - name: myapp-gateway
  hostnames:
  - "myapp.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: myapp
      port: 80
```

**고급 기능** - 트래픽 분할 (Canary):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: myapp-canary
spec:
  parentRefs:
  - name: myapp-gateway
  hostnames:
  - "myapp.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: myapp-v1
      port: 80
      weight: 90
    - name: myapp-v2
      port: 80
      weight: 10
```

**gRPC 지원**:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata:
  name: grpc-route
spec:
  parentRefs:
  - name: myapp-gateway
  hostnames:
  - "grpc.example.com"
  rules:
  - backendRefs:
    - name: grpc-service
      port: 50051
```

**헤더 기반 라우팅**:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: header-based-route
spec:
  parentRefs:
  - name: myapp-gateway
  rules:
  - matches:
    - headers:
      - name: X-Version
        value: v2
    backendRefs:
    - name: myapp-v2
      port: 80
  - backendRefs:
    - name: myapp-v1
      port: 80
```

**모니터링**:

```bash
# ALB Controller 로그 확인
kubectl logs -n alb-infra -l app=alb-controller

# Gateway 상태 확인
kubectl get gateway myapp-gateway -o yaml

# HTTPRoute 상태 확인
kubectl get httproute myapp-route -o yaml

# ApplicationLoadBalancer 상태 확인
kubectl get applicationloadbalancer -n alb-infra
```

**장점**:
- ✅ Kubernetes Gateway API 표준 (이식성 향상)
- ✅ AGIC보다 빠른 배포 속도
- ✅ 더 간단한 설정 및 관리
- ✅ 자동 스케일링 (수동 설정 불필요)
- ✅ 다양한 프로토콜 지원 (gRPC, TCP, TLS)
- ✅ 트래픽 분할 및 헤더 기반 라우팅 용이
- ✅ WAF v2와 네이티브 통합

**단점**:
- ⚠️ 비교적 새로운 서비스 (2023년 GA)
- ⚠️ 일부 고급 기능은 아직 개발 중
- ❌ 멀티 클라우드 미지원

#### 선택 가이드

**Nginx Ingress를 선택하는 경우**:
- 비용 효율성이 중요한 경우
- 빠른 배포와 변경이 필요한 경우
- Canary 배포, A/B 테스팅이 필요한 경우
- 다양한 Ingress 기능이 필요한 경우
- 멀티 클라우드 전략을 고려하는 경우

**AGC를 선택하는 경우** (권장 - Azure 환경):
- Azure 네이티브 솔루션을 선호하는 경우
- WAF가 필요하지만 빠른 배포도 중요한 경우
- Kubernetes Gateway API 표준을 따르고 싶은 경우
- gRPC, WebSocket 등 다양한 프로토콜 지원이 필요한 경우
- 자동 스케일링이 필요한 경우
- 최신 Azure 기능과 통합이 필요한 경우

**AGIC를 선택하는 경우**:
- 기존 Application Gateway 인프라를 활용하는 경우
- 매우 복잡한 라우팅 규칙이 필요한 경우
- Private Link를 통한 보안 연결이 필요한 경우
- 레거시 시스템과의 통합이 필요한 경우

**Internal Load Balancer**:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: internal-app
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  ports:
  - port: 80
  selector:
    app: internal-app
```

---

## 보안

### 1. Azure AD 통합 및 RBAC

**Azure AD 인증 활성화**:

```bash
# AAD 통합 활성화
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --enable-aad \
  --aad-admin-group-object-ids $AAD_GROUP_ID
```

**Role Binding 예시**:

```yaml
# cluster-admin-binding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: aad-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # AAD Group ID
---
# namespace-reader-binding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-team-reader
  namespace: development
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"  # Dev Team AAD Group
```

### 2. Pod Security Standards

**Pod Security Admission**:

```yaml
# namespace with pod security
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
---
# baseline for less restrictive namespaces
apiVersion: v1
kind: Namespace
metadata:
  name: development
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: baseline
    pod-security.kubernetes.io/warn: baseline
```

**Restricted Pod Security Context**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
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
      - name: app
        image: myapp:1.0
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 1000
          capabilities:
            drop:
              - ALL
        volumeMounts:
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: tmp
        emptyDir: {}
```

### 3. Workload Identity (권장 - 최신 인증 방식)

Workload Identity는 Pod가 Azure 리소스에 접근할 때 사용하는 최신 인증 방식입니다. 기존 Pod Identity를 대체하며 더 안전하고 관리가 쉽습니다.

**특징**:
- ✅ OIDC 기반 표준 인증
- ✅ Pod Identity보다 안전하고 간단
- ✅ Azure AD와 네이티브 통합
- ✅ 별도 인프라 컴포넌트 불필요
- ✅ 노드 레벨 권한 불필요

**Workload Identity 활성화**:

```bash
# 1. 클러스터에 Workload Identity 활성화
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --enable-oidc-issuer \
  --enable-workload-identity

# 2. OIDC Issuer URL 가져오기
OIDC_ISSUER=$(az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --query "oidcIssuerProfile.issuerUrl" \
  --output tsv)

echo $OIDC_ISSUER
```

**User Assigned Managed Identity 생성**:

```bash
# 3. Managed Identity 생성
az identity create \
  --resource-group $RESOURCE_GROUP \
  --name myWorkloadIdentity

# Identity Client ID 가져오기
CLIENT_ID=$(az identity show \
  --resource-group $RESOURCE_GROUP \
  --name myWorkloadIdentity \
  --query 'clientId' \
  --output tsv)

echo $CLIENT_ID
```

**Azure 리소스 권한 부여** (예: Key Vault):

```bash
# 4. Key Vault에 대한 권한 부여
az keyvault set-policy \
  --name myKeyVault \
  --object-id $(az identity show \
    --resource-group $RESOURCE_GROUP \
    --name myWorkloadIdentity \
    --query principalId \
    --output tsv) \
  --secret-permissions get list
```

**Federated Identity Credential 생성**:

```bash
# 5. Kubernetes ServiceAccount와 Azure Identity 연결
az identity federated-credential create \
  --name myFederatedCredential \
  --identity-name myWorkloadIdentity \
  --resource-group $RESOURCE_GROUP \
  --issuer $OIDC_ISSUER \
  --subject system:serviceaccount:default:workload-identity-sa \
  --audience api://AzureADTokenExchange
```

**Kubernetes ServiceAccount 생성**:

```yaml
# service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: workload-identity-sa
  namespace: default
  annotations:
    azure.workload.identity/client-id: "${CLIENT_ID}"
  labels:
    azure.workload.identity/use: "true"
```

**Pod에서 Workload Identity 사용**:

```yaml
# pod-with-workload-identity.yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
  namespace: default
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: workload-identity-sa
  containers:
  - name: myapp
    image: myapp:1.0
    env:
    - name: AZURE_CLIENT_ID
      value: "${CLIENT_ID}"
    # Azure SDK가 자동으로 Workload Identity 사용
```

**Python 코드 예시** (Azure SDK 사용):

```python
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

# Workload Identity가 자동으로 사용됨
credential = DefaultAzureCredential()
secret_client = SecretClient(
    vault_url="https://mykeyvault.vault.azure.net",
    credential=credential
)

# Secret 가져오기
secret = secret_client.get_secret("database-password")
print(f"Secret value: {secret.value}")
```

**검증**:

```bash
# Pod 로그 확인
kubectl logs myapp

# ServiceAccount 확인
kubectl describe sa workload-identity-sa

# Pod에 annotation이 주입되었는지 확인
kubectl get pod myapp -o yaml | grep azure.workload.identity
```

**Best Practices**:
- ✅ 네임스페이스별로 ServiceAccount 분리
- ✅ 최소 권한 원칙 적용 (필요한 권한만 부여)
- ✅ Federated Credential의 subject를 정확히 지정
- ✅ Azure Policy로 Workload Identity 사용 강제
- ❌ 하나의 Identity를 여러 용도로 재사용하지 않기

### 4. Azure Key Vault 통합

**Secrets Store CSI Driver**:

```bash
# CSI Driver 애드온 활성화
az aks enable-addons \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --addons azure-keyvault-secrets-provider
```

**SecretProviderClass**:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-keyvault
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: ""
    keyvaultName: "myKeyVault"
    cloudName: ""
    objects: |
      array:
        - |
          objectName: database-password
          objectType: secret
          objectVersion: ""
    tenantId: "your-tenant-id"
```

**Workload Identity와 함께 사용**:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-keyvault-workload-identity
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "false"
    clientID: "${CLIENT_ID}"  # Workload Identity Client ID
    keyvaultName: "myKeyVault"
    cloudName: ""
    objects: |
      array:
        - |
          objectName: database-password
          objectType: secret
    tenantId: "your-tenant-id"
```

**Pod에서 사용**:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: workload-identity-sa
  containers:
  - name: myapp
    image: myapp:1.0
    volumeMounts:
    - name: secrets-store
      mountPath: "/mnt/secrets"
      readOnly: true
  volumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: azure-keyvault-workload-identity
```

### 5. 이미지 보안 - Trivy

Trivy는 컨테이너 이미지, 파일시스템, Git 리포지토리의 취약점을 스캔하는 오픈소스 보안 스캐너입니다.

**특징**:
- ✅ 포괄적인 취약점 스캔 (OS 패키지, 애플리케이션 의존성)
- ✅ 빠르고 정확한 스캔
- ✅ CI/CD 파이프라인 통합 용이
- ✅ Kubernetes 매니페스트 보안 검사
- ✅ 무료 오픈소스

**Trivy 설치**:

```bash
# Linux
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install trivy

# macOS
brew install trivy
```

**이미지 취약점 스캔**:

```bash
# 기본 스캔
trivy image nginx:1.27

# 심각도 필터링 (HIGH, CRITICAL만)
trivy image --severity HIGH,CRITICAL nginx:1.27

# JSON 출력
trivy image --format json --output results.json nginx:1.27

# 특정 취약점 무시
trivy image --ignore-unfixed nginx:1.27
```

**Azure Container Registry 이미지 스캔**:

```bash
# ACR 로그인
az acr login --name myregistry

# ACR 이미지 스캔
trivy image myregistry.azurecr.io/myapp:1.0
```

**Kubernetes 매니페스트 스캔**:

```bash
# YAML 파일 보안 검사
trivy config deployment.yaml

# 전체 디렉토리 스캔
trivy config ./k8s-manifests/

# Helm 차트 스캔
trivy config ./my-chart/
```

**CI/CD 파이프라인 통합** (GitHub Actions):

```yaml
# .github/workflows/trivy-scan.yml
name: Trivy Security Scan

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout code
      uses: actions/checkout@v3

    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: 'myregistry.azurecr.io/myapp:${{ github.sha }}'
        format: 'sarif'
        output: 'trivy-results.sarif'
        severity: 'CRITICAL,HIGH'

    - name: Upload Trivy results to GitHub Security
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: 'trivy-results.sarif'

    - name: Fail build on critical vulnerabilities
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: 'myregistry.azurecr.io/myapp:${{ github.sha }}'
        exit-code: '1'
        severity: 'CRITICAL'
```

**Azure DevOps 파이프라인**:

```yaml
# azure-pipelines.yml
trigger:
  - main

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: Docker@2
  inputs:
    containerRegistry: 'myACR'
    repository: 'myapp'
    command: 'build'
    Dockerfile: '**/Dockerfile'
    tags: '$(Build.BuildId)'

- script: |
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
    echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
    sudo apt-get update
    sudo apt-get install trivy
  displayName: 'Install Trivy'

- script: |
    trivy image --severity HIGH,CRITICAL --exit-code 1 myregistry.azurecr.io/myapp:$(Build.BuildId)
  displayName: 'Scan image with Trivy'
```

**Trivy Operator (Kubernetes 내 지속적 스캔)**:

```bash
# Trivy Operator 설치 (Helm)
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm repo update

helm install trivy-operator aqua/trivy-operator \
  --namespace trivy-system \
  --create-namespace \
  --set trivy.ignoreUnfixed=true
```

**VulnerabilityReport 확인**:

```bash
# 클러스터 내 모든 취약점 리포트 조회
kubectl get vulnerabilityreports -A

# 특정 워크로드의 취약점 확인
kubectl get vulnerabilityreport -n default

# 상세 내용 확인
kubectl describe vulnerabilityreport <report-name> -n default
```

**정책 적용** (Admission Controller):

```yaml
# 높은 심각도 취약점이 있는 이미지 배포 차단
apiVersion: v1
kind: ConfigMap
metadata:
  name: trivy-operator-policies
  namespace: trivy-system
data:
  policy.rego: |
    package trivy
    
    deny[msg] {
      input.vulnerabilities[_].severity == "CRITICAL"
      msg := "Image contains CRITICAL vulnerabilities"
    }
    
    deny[msg] {
      count([v | v := input.vulnerabilities[_]; v.severity == "HIGH"]) > 10
      msg := "Image contains more than 10 HIGH vulnerabilities"
    }
```

**Best Practices**:
- ✅ 모든 이미지를 프로덕션 배포 전 스캔
- ✅ CI/CD 파이프라인에 자동 스캔 통합
- ✅ CRITICAL 취약점 발견 시 빌드 실패 처리
- ✅ 정기적인 실행 중인 이미지 재스캔 (Trivy Operator)
- ✅ 베이스 이미지를 최신 패치 버전으로 유지
- ✅ 취약점 리포트를 보안 팀과 공유
- ❌ 오래된 이미지를 프로덕션에 배포하지 않기

### 6. 이전 섹션

**Pod에서 사용**:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-secrets
spec:
  containers:
  - name: app
    image: myapp:1.0
    volumeMounts:
    - name: secrets-store
      mountPath: "/mnt/secrets-store"
      readOnly: true
    env:
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: database-credentials
          key: database-password
  volumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: "azure-keyvault"
```

### 4. Image Security

**Azure Container Registry (ACR) 통합**:

```bash
# ACR 연결
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --attach-acr myregistry
```

**이미지 스캔 및 정책**:

```bash
# Defender for Containers 활성화
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --enable-defender
```

**ImagePullPolicy 권장 사항**:

```yaml
containers:
- name: app
  image: myregistry.azurecr.io/myapp:v1.2.3
  imagePullPolicy: IfNotPresent  # 프로덕션: 특정 태그 사용
```

### 5. Network Security

**Private Cluster**:

```bash
# Private Cluster 생성
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --enable-private-cluster \
  --private-dns-zone system
```

**Authorized IP Ranges**:

```bash
# API Server 접근 제한
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --api-server-authorized-ip-ranges "203.0.113.0/24,198.51.100.0/24"
```

---

## 모니터링 및 로깅

### 1. Azure Monitor 통합

**Container Insights 활성화**:

```bash
# 모니터링 애드온 활성화
az aks enable-addons \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --addons monitoring \
  --workspace-resource-id $WORKSPACE_ID
```

### 2. Prometheus 및 Grafana

**Managed Prometheus**:

```bash
# Azure Monitor Workspace 생성
az monitor account create \
  --name myAzureMonitorWorkspace \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION

# Prometheus 메트릭 수집 활성화
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --enable-azure-monitor-metrics
```

### 3. 로깅 전략

**Container Logs**:

```bash
# Pod 로그 조회
az aks command invoke \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --command "kubectl logs -f deployment/myapp -n production"
```

**Diagnostic Settings**:

```bash
# 진단 설정 구성
az monitor diagnostic-settings create \
  --name aks-diagnostics \
  --resource $(az aks show -g $RESOURCE_GROUP -n $CLUSTER --query id -o tsv) \
  --workspace $WORKSPACE_ID \
  --logs '[{"category":"kube-apiserver","enabled":true},
          {"category":"kube-controller-manager","enabled":true},
          {"category":"kube-scheduler","enabled":true},
          {"category":"kube-audit","enabled":true},
          {"category":"cluster-autoscaler","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]'
```

---

## 리소스 관리

### 1. Resource Quotas

**네임스페이스별 쿼터**:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "100"
    requests.memory: 200Gi
    limits.cpu: "200"
    limits.memory: 400Gi
    persistentvolumeclaims: "20"
    services.loadbalancers: "5"
```

### 2. LimitRange

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: production-limits
  namespace: production
spec:
  limits:
  - max:
      cpu: "4"
      memory: 8Gi
    min:
      cpu: "100m"
      memory: 128Mi
    default:
      cpu: "500m"
      memory: 512Mi
    defaultRequest:
      cpu: "200m"
      memory: 256Mi
    type: Container
  - max:
      cpu: "8"
      memory: 16Gi
    min:
      cpu: "200m"
      memory: 256Mi
    type: Pod
```

### 3. Vertical Pod Autoscaler (VPA)

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: myapp-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  updatePolicy:
    updateMode: "Auto"
  resourcePolicy:
    containerPolicies:
    - containerName: "*"
      minAllowed:
        cpu: 100m
        memory: 128Mi
      maxAllowed:
        cpu: 2
        memory: 2Gi
```

---

## 고가용성

### 1. Pod Disruption Budget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: myapp
---
# 또는 percentage 사용
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb-percentage
spec:
  maxUnavailable: 25%
  selector:
    matchLabels:
      app: myapp
```

### 2. Multi-Zone Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ha-app
spec:
  replicas: 6
  template:
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: ha-app
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: ha-app
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app: ha-app
              topologyKey: kubernetes.io/hostname
```

### 3. Backup 및 Disaster Recovery

**Velero 설치**:

```bash
# Velero CLI 설치
wget https://github.com/vmware-tanzu/velero/releases/download/v1.12.0/velero-v1.12.0-linux-amd64.tar.gz
tar -xvf velero-v1.12.0-linux-amd64.tar.gz
sudo mv velero-v1.12.0-linux-amd64/velero /usr/local/bin/

# Azure Storage 계정 생성
AZURE_BACKUP_RESOURCE_GROUP=velero-backups
az group create -n $AZURE_BACKUP_RESOURCE_GROUP --location $LOCATION

AZURE_STORAGE_ACCOUNT_ID="velero$(uuidgen | cut -d '-' -f5 | tr '[A-Z]' '[a-z]')"
az storage account create \
  --name $AZURE_STORAGE_ACCOUNT_ID \
  --resource-group $AZURE_BACKUP_RESOURCE_GROUP \
  --sku Standard_GRS \
  --encryption-services blob \
  --https-only true \
  --kind BlobStorage \
  --access-tier Hot

# Velero 설치
velero install \
  --provider azure \
  --plugins velero/velero-plugin-for-microsoft-azure:v1.8.0 \
  --bucket velero \
  --secret-file ./credentials-velero \
  --backup-location-config resourceGroup=$AZURE_BACKUP_RESOURCE_GROUP,storageAccount=$AZURE_STORAGE_ACCOUNT_ID \
  --snapshot-location-config apiTimeout=5m,resourceGroup=$AZURE_BACKUP_RESOURCE_GROUP
```

**백업 스케줄**:

```bash
# 일일 백업
velero schedule create daily-backup \
  --schedule="0 2 * * *" \
  --include-namespaces production,staging

# 네임스페이스별 백업
velero backup create production-backup \
  --include-namespaces production \
  --storage-location default
```

---

## 비용 최적화

### 1. 노드 Right-Sizing

**추천 VM 크기**:

| 워크로드 | VM 크기 | vCPU | Memory | 용도 |
|---------|---------|------|--------|------|
| 개발/테스트 | Standard_B2s | 2 | 4 GB | 소규모 워크로드 |
| 일반 앱 | Standard_D4s_v3 | 4 | 16 GB | 범용 애플리케이션 |
| 메모리 집약 | Standard_E4s_v3 | 4 | 32 GB | 데이터베이스, 캐시 |
| 컴퓨팅 집약 | Standard_F4s_v2 | 4 | 8 GB | CPU 집약적 작업 |
| GPU | Standard_NC6s_v3 | 6 | 112 GB | ML/AI 워크로드 |

### 2. Spot Instances

```bash
# Spot Node Pool 생성
az aks nodepool add \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER \
  --name spotpool \
  --priority Spot \
  --eviction-policy Delete \
  --spot-max-price -1 \
  --node-count 3 \
  --min-count 1 \
  --max-count 10 \
  --enable-cluster-autoscaler \
  --node-vm-size Standard_D4s_v3 \
  --node-taints kubernetes.azure.com/scalesetpriority=spot:NoSchedule \
  --labels kubernetes.azure.com/scalesetpriority=spot
```

**Spot Pod 배포**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch-processor
spec:
  replicas: 10
  template:
    spec:
      tolerations:
      - key: kubernetes.azure.com/scalesetpriority
        operator: Equal
        value: spot
        effect: NoSchedule
      nodeSelector:
        kubernetes.azure.com/scalesetpriority: spot
      containers:
      - name: processor
        image: myapp:1.0
```

### 3. Cluster Autoscaler 최적화

```bash
# Cluster Autoscaler 프로필 설정
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --cluster-autoscaler-profile \
    scale-down-delay-after-add=10m \
    scale-down-unneeded-time=10m \
    scale-down-utilization-threshold=0.5 \
    max-graceful-termination-sec=600
```

### 4. Azure Hybrid Benefit

```bash
# Windows 노드에 Azure Hybrid Benefit 적용
az aks nodepool add \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER \
  --name winpool \
  --os-type Windows \
  --node-count 2 \
  --enable-ahub
```

---

## 운영 체크리스트

### 프로덕션 배포 전 체크리스트

#### 보안 ✅

- [ ] Azure AD 통합 활성화
- [ ] RBAC 역할 및 바인딩 구성
- [ ] Network Policy 적용
- [ ] Pod Security Standards 적용 (Restricted)
- [ ] Private Cluster 또는 Authorized IP 설정
- [ ] Azure Key Vault 통합
- [ ] ACR 이미지 스캔 활성화
- [ ] Defender for Containers 활성화
- [ ] TLS/SSL 인증서 구성

#### 고가용성 ✅

- [ ] 다중 가용성 영역 사용 (최소 3개)
- [ ] 노드 풀 최소 3개 노드
- [ ] Pod Disruption Budget 설정
- [ ] Anti-Affinity 규칙 적용
- [ ] Topology Spread Constraints 구성
- [ ] Liveness/Readiness Probe 설정
- [ ] 백업 솔루션 구성 (Velero)

#### 리소스 관리 ✅

- [ ] Resource Requests/Limits 설정
- [ ] ResourceQuota 적용
- [ ] LimitRange 구성
- [ ] HPA/VPA 설정
- [ ] Cluster Autoscaler 활성화
- [ ] PodDisruptionBudget 설정

#### 모니터링 ✅

- [ ] Azure Monitor Container Insights 활성화
- [ ] Prometheus/Grafana 구성
- [ ] 알림 규칙 설정
- [ ] Diagnostic Logs 활성화
- [ ] Application Insights 통합

#### 네트워킹 ✅

- [ ] Azure CNI 사용
- [ ] Load Balancer SKU: Standard
- [ ] Ingress Controller 구성
- [ ] DNS 설정 확인
- [ ] Egress 트래픽 제어

#### 운영 ✅

- [ ] 자동 업그레이드 채널 설정
- [ ] 유지보수 윈도우 구성
- [ ] 태그 정책 적용
- [ ] Cost Management 설정
- [ ] GitOps 워크플로우 구성

### 일일 운영 체크리스트

```bash
#!/bin/bash
# daily-health-check.sh

echo "🔍 AKS Daily Health Check"
echo "========================="

# 1. 클러스터 상태
echo "📊 Cluster Status:"
az aks show -g $RESOURCE_GROUP -n $CLUSTER --query "powerState" -o table

# 2. 노드 상태
echo -e "\n🖥️ Node Status:"
kubectl get nodes

# 3. Pod 상태
echo -e "\n📦 Pod Status:"
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed

# 4. PVC 상태
echo -e "\n💾 PVC Status:"
kubectl get pvc --all-namespaces | grep -v Bound

# 5. 리소스 사용량
echo -e "\n📈 Resource Usage:"
kubectl top nodes

# 6. 이벤트 확인
echo -e "\n⚠️ Recent Events:"
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20

# 7. 인증서 만료 확인
echo -e "\n🔐 Certificate Expiry:"
kubectl get secret --all-namespaces -o json | \
  jq -r '.items[] | select(.type=="kubernetes.io/tls") | 
  "\(.metadata.namespace)/\(.metadata.name)"'
```

### 주간 운영 체크리스트

- [ ] 백업 확인 및 복원 테스트
- [ ] 리소스 사용량 분석
- [ ] 비용 리뷰
- [ ] 보안 스캔 결과 검토
- [ ] 업데이트 및 패치 확인
- [ ] 용량 계획 리뷰

### 월간 운영 체크리스트

- [ ] Disaster Recovery 테스트
- [ ] 보안 감사
- [ ] 성능 벤치마크
- [ ] SLA/SLO 리뷰
- [ ] 아키텍처 리뷰
- [ ] 비용 최적화 분석

---

## Security Baseline

### CIS Kubernetes Benchmark

**자동 스캔**:

```bash
# kube-bench 설치 및 실행
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-aks.yaml

# 결과 확인
kubectl logs -f job/kube-bench

# 결과 저장
kubectl logs job/kube-bench > kube-bench-results.txt
```

### Azure Policy for AKS

**내장 정책 할당**:

```bash
# Azure Policy 애드온 활성화
az aks enable-addons \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --addons azure-policy

# 정책 할당 예시
az policy assignment create \
  --name 'enforce-https-ingress' \
  --policy '/providers/Microsoft.Authorization/policyDefinitions/1a5b4dca-0b6f-4cf5-907c-56316bc1bf3d' \
  --scope $(az aks show -g $RESOURCE_GROUP -n $CLUSTER --query id -o tsv)
```

**권장 정책**:

1. Enforce HTTPS ingress
2. Ensure container CPU and memory limits
3. Do not allow privileged containers
4. Ensure services only use allowed external IPs
5. Ensure only allowed container images

### 침투 테스트 가이드라인

**정기 보안 테스트**:

```bash
# Kubescape 실행
curl -s https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh | /bin/bash
kubescape scan --compliance-threshold 80 --format json --output results.json
```

---

## 추가 리소스

### 공식 문서

- [AKS Best Practices](https://learn.microsoft.com/azure/aks/best-practices)
- [AKS Baseline Architecture](https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/baseline-aks)
- [Azure Well-Architected Framework](https://learn.microsoft.com/azure/well-architected/)

### 도구

- [Azure CLI](https://learn.microsoft.com/cli/azure/)
- [kubectl](https://kubernetes.io/docs/reference/kubectl/)
- [Helm](https://helm.sh/)
- [Velero](https://velero.io/)
- [Kube-bench](https://github.com/aquasecurity/kube-bench)
- [Kubescape](https://github.com/kubescape/kubescape)

### 커뮤니티

- [AKS GitHub](https://github.com/Azure/AKS)
- [CNCF Slack](https://slack.cncf.io/)
- [Kubernetes Slack](https://slack.k8s.io/)
