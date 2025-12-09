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

**Azure CNI (권장 - 프로덕션)**:

- ✅ 각 Pod가 VNet IP를 받음
- ✅ Azure 네트워크 정책 지원
- ✅ Virtual Node 지원
- ❌ IP 주소 소비가 큼

**Kubenet (개발/테스트)**:

- ✅ IP 주소 절약
- ❌ 추가 라우팅 필요
- ❌ Virtual Node 미지원

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

### 3. Ingress 및 Load Balancer

**Application Gateway Ingress Controller (AGIC)**:

```bash
# AGIC 애드온 활성화
az aks enable-addons \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --addons ingress-appgw \
  --appgw-name myApplicationGateway \
  --appgw-subnet-cidr "10.2.0.0/16"
```

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

### 3. Azure Key Vault 통합

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
