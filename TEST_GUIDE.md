# AKS Workshop 테스트 가이드

이 문서는 AKS Workshop의 모든 실습 코드를 테스트하는 방법을 설명합니다.

## 📋 목차

- [사전 준비](#사전-준비)
- [테스트 환경 설정](#테스트-환경-설정)
- [자동 테스트 실행](#자동-테스트-실행)
- [수동 테스트 가이드](#수동-테스트-가이드)
- [테스트 결과 검증](#테스트-결과-검증)
- [리소스 정리](#리소스-정리)
- [문제 해결](#문제-해결)

## 사전 준비

### 필수 도구 설치

```bash
# Azure CLI 설치
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# kubectl 설치
sudo az aks install-cli

# Helm 설치
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Azure 로그인

```bash
# Azure 계정 로그인
az login

# 구독 설정 (필요한 경우)
az account set --subscription <subscription-id>
```

## 테스트 환경 설정

### 1. 환경 변수 설정

```bash
# env.sh 파일 확인
cat env.sh
```

내용:
```bash
#!/bin/bash
# AKS 클러스터 기본 환경 변수
export RESOURCE_GROUP=aks-workshop-rg
export CLUSTER=aks-workshop
export LOCATION=koreacentral
export K8S_VERSION='1.32.9'
export NODE_COUNT=3
```

환경 변수 로드:
```bash
source ./env.sh
```

### 2. AKS 클러스터 생성

```bash
# 리소스 그룹 생성
az group create --location $LOCATION --resource-group $RESOURCE_GROUP

# AKS 클러스터 생성 (약 5-10분 소요)
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --location $LOCATION \
  --node-count $NODE_COUNT \
  --kubernetes-version $K8S_VERSION \
  --network-plugin azure \
  --generate-ssh-keys

# 클러스터 자격 증명 가져오기
az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER --overwrite-existing
```

### 3. 클러스터 확인

```bash
# 클러스터 정보 확인
kubectl cluster-info

# 노드 확인
kubectl get nodes
```

예상 출력:
```
NAME                                STATUS   ROLES   AGE   VERSION
aks-nodepool1-12345678-vmss000000   Ready    agent   5m    v1.32.9
aks-nodepool1-12345678-vmss000001   Ready    agent   5m    v1.32.9
aks-nodepool1-12345678-vmss000002   Ready    agent   5m    v1.32.9
```

## 자동 테스트 실행

### 전체 테스트 실행

```bash
# 환경 변수 로드
source ./env.sh

# 테스트 스크립트 실행 (결과를 파일로 저장)
./test-workshop.sh 2>&1 | tee test-results.log
```

### 테스트 스크립트 구조

`test-workshop.sh`는 다음 모듈을 순차적으로 테스트합니다:

1. **Kubernetes 기초**
   - Basic Deployment
   - Service (ClusterIP, NodePort, LoadBalancer)
   - ConfigMap
   - Secret

2. **고급 Kubernetes**
   - Volumes
   - Probes (Liveness, Readiness)

3. **Pod 스케줄링**
   - NodeSelector
   - Affinity/Anti-Affinity
   - Taints & Tolerations

4. **오토스케일링**
   - Resource Requests/Limits
   - Horizontal Pod Autoscaler

### 테스트 실행 로그 예시

```
[INFO] =========================================
[INFO] AKS Workshop 테스트 시작
[INFO] =========================================
[INFO] 환경 변수 확인 중...
[INFO] 환경 변수 확인 완료: CLUSTER=aks-workshop, RESOURCE_GROUP=aks-workshop-rg
[INFO] 클러스터 연결 확인 중...
[INFO] 클러스터 연결 확인 완료

[INFO] =========================================
[INFO] 기본 Deployment 테스트
[INFO] =========================================
[INFO] 테스트 네임스페이스 생성: test-basic-deploy
[INFO] Deployment 생성...
deployment.apps/test-workload created
[INFO] Pod 준비 대기...
pod/test-workload-xxxxx condition met
[INFO] Deployment 확인...
NAME            READY   UP-TO-DATE   AVAILABLE   AGE
test-workload   3/3     3            3           30s
```

## 수동 테스트 가이드

자동 테스트 외에 각 모듈을 수동으로 테스트할 수 있습니다.

### Kubernetes 기초

#### 1.1 Deployment 테스트

```bash
# 네임스페이스 생성
kubectl create namespace test-deploy

# Deployment 생성
kubectl apply -n test-deploy -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
EOF

# 확인
kubectl get deployment -n test-deploy
kubectl get pods -n test-deploy
```

#### 1.2 Service 테스트

```bash
# ClusterIP Service
kubectl expose deployment nginx-deployment --port=80 --target-port=80 --name=nginx-service -n test-deploy

# 확인
kubectl get svc -n test-deploy
```

#### 1.3 ConfigMap 테스트

```bash
kubectl create configmap test-config --from-literal=key1=value1 -n test-deploy
kubectl get configmap test-config -n test-deploy -o yaml
```

#### 1.4 Secret 테스트

```bash
kubectl create secret generic test-secret --from-literal=password=mypassword -n test-deploy
kubectl get secret test-secret -n test-deploy
```

### 고급 Kubernetes

#### 3.1 Volume 테스트

```bash
kubectl apply -n test-deploy -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-volume
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: cache-volume
      mountPath: /cache
  volumes:
  - name: cache-volume
    emptyDir: {}
EOF

# 확인
kubectl get pod test-volume -n test-deploy
kubectl describe pod test-volume -n test-deploy | grep -A 5 Volumes
```

#### 3.2 Probes 테스트

```bash
kubectl apply -n test-deploy -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-probes
spec:
  containers:
  - name: app
    image: nginx
    livenessProbe:
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 3
      periodSeconds: 3
    readinessProbe:
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 5
      periodSeconds: 5
EOF

# 확인
kubectl get pod test-probes -n test-deploy
kubectl describe pod test-probes -n test-deploy | grep -A 10 Liveness
```

### Pod 스케줄링

#### 5.1 NodeSelector 테스트

```bash
# 노드에 레이블 추가
kubectl label nodes <node-name> disktype=ssd

# Pod 생성
kubectl apply -n test-deploy -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-node-selector
spec:
  nodeSelector:
    disktype: ssd
  containers:
  - name: nginx
    image: nginx
EOF

# 확인
kubectl get pod test-node-selector -n test-deploy -o wide
```

### 오토스케일링

#### 7.1 HPA 테스트

```bash
# Deployment에 리소스 설정
kubectl apply -n test-deploy -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: php-apache
spec:
  replicas: 1
  selector:
    matchLabels:
      app: php-apache
  template:
    metadata:
      labels:
        app: php-apache
    spec:
      containers:
      - name: php-apache
        image: registry.k8s.io/hpa-example
        ports:
        - containerPort: 80
        resources:
          limits:
            cpu: 500m
          requests:
            cpu: 200m
EOF

# HPA 생성
kubectl autoscale deployment php-apache --cpu-percent=50 --min=1 --max=10 -n test-deploy

# 확인
kubectl get hpa -n test-deploy
```

## 테스트 결과 검증

### 체크리스트

각 모듈의 테스트 결과를 다음 항목으로 검증합니다:

- [ ] **Kubernetes 기초**
  - [ ] Deployment가 READY 상태 (3/3)
  - [ ] Service가 ClusterIP 할당됨
  - [ ] ConfigMap이 생성되고 값 확인 가능
  - [ ] Secret이 생성되고 base64 인코딩됨

- [ ] **고급 Kubernetes**
  - [ ] Volume이 Pod에 마운트됨
  - [ ] Liveness Probe가 정상 동작
  - [ ] Readiness Probe가 정상 동작

- [ ] **Pod 스케줄링**
  - [ ] NodeSelector로 특정 노드에 스케줄링됨
  - [ ] Affinity 규칙이 적용됨

- [ ] **오토스케일링**
  - [ ] Resource Requests/Limits 설정됨
  - [ ] HPA가 생성되고 메트릭 수집 중

### 로그 확인

```bash
# 전체 테스트 로그 확인
cat test-results.log

# 에러만 확인
grep -i error test-results.log

# 성공한 테스트 확인
grep -i "✓" test-results.log
```

## 리소스 정리

### 테스트 리소스만 정리

```bash
# 테스트 네임스페이스만 삭제
./cleanup-workshop.sh --test
```

### 모든 리소스 정리

```bash
# Bookinfo, Istio, 테스트 리소스 모두 삭제
./cleanup-workshop.sh --all
```

### 클러스터 완전 삭제

```bash
# 클러스터 및 리소스 그룹 삭제
./cleanup-workshop.sh --delete-cluster
```

또는 수동으로:

```bash
# 리소스 그룹 삭제 (모든 리소스 포함)
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

## 문제 해결

### 일반적인 문제

#### 1. Pod가 Pending 상태

```bash
# Pod 상태 확인
kubectl describe pod <pod-name> -n <namespace>

# 이벤트 확인
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

**원인**: 리소스 부족, 노드 선택자 불일치 등

**해결**: 
- 노드 리소스 확인: `kubectl top nodes`
- 노드 레이블 확인: `kubectl get nodes --show-labels`

#### 2. ImagePullBackOff 오류

```bash
kubectl describe pod <pod-name> -n <namespace>
```

**원인**: 이미지를 가져올 수 없음

**해결**:
- 이미지 이름 확인
- 레지스트리 인증 확인
- 네트워크 연결 확인

#### 3. CrashLoopBackOff 오류

```bash
# 로그 확인
kubectl logs <pod-name> -n <namespace>

# 이전 컨테이너 로그 확인
kubectl logs <pod-name> -n <namespace> --previous
```

**원인**: 애플리케이션 오류, 잘못된 설정 등

**해결**:
- 로그에서 오류 메시지 확인
- 환경 변수 및 ConfigMap 확인
- Liveness/Readiness Probe 설정 확인

#### 4. Service 연결 실패

```bash
# Service 엔드포인트 확인
kubectl get endpoints <service-name> -n <namespace>

# Service 상세 정보
kubectl describe svc <service-name> -n <namespace>
```

**원인**: 셀렉터 불일치, 포트 설정 오류

**해결**:
- Pod 레이블과 Service 셀렉터 일치 확인
- 포트 매핑 확인

### 디버깅 팁

```bash
# 특정 네임스페이스의 모든 리소스 확인
kubectl get all -n <namespace>

# 리소스 YAML 출력
kubectl get <resource-type> <resource-name> -n <namespace> -o yaml

# 실시간 로그 확인
kubectl logs -f <pod-name> -n <namespace>

# Pod 내부 접속
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash

# 네트워크 테스트
kubectl run test-pod --rm -it --image=busybox -n <namespace> -- /bin/sh
```

## 테스트 자동화 CI/CD

GitHub Actions를 사용한 자동 테스트 예시:

```yaml
name: AKS Workshop Tests

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    - name: Azure Login
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    
    - name: Setup Environment
      run: |
        source ./env.sh
        echo "CLUSTER=$CLUSTER" >> $GITHUB_ENV
        echo "RESOURCE_GROUP=$RESOURCE_GROUP" >> $GITHUB_ENV
    
    - name: Get AKS Credentials
      run: |
        az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER
    
    - name: Run Tests
      run: |
        chmod +x test-workshop.sh
        ./test-workshop.sh
    
    - name: Cleanup
      if: always()
      run: |
        chmod +x cleanup-workshop.sh
        ./cleanup-workshop.sh --test
```

## 참고 자료

- [AKS Workshop 문서](https://dotnetpower.github.io/aks-workshop/)
- [Kubernetes 공식 문서](https://kubernetes.io/docs/)
- [Azure AKS 문서](https://learn.microsoft.com/ko-kr/azure/aks/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)

## 기여

테스트 스크립트 개선이나 새로운 테스트 케이스 추가는 언제나 환영합니다!

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request
