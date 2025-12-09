# AKS Workshop - 테스트 및 검증 가이드

이 문서는 AKS Workshop의 모든 실습 코드를 테스트하고 검증하는 가이드입니다.

## 테스트 환경 준비

### 1. 환경 변수 설정

```bash
# istio-env.sh 파일 사용
source ./istio-env.sh

# 또는 직접 설정
export CLUSTER=istio-addon-lab
export RESOURCE_GROUP=gmarket-istio-lab
export LOCATION=koreacentral
export K8S_VERSION=1.27.7
```

### 2. 클러스터 연결 확인

```bash
# 클러스터 정보 확인
kubectl cluster-info

# 노드 확인
kubectl get nodes

# 네임스페이스 확인
kubectl get namespaces
```

## 테스트 스크립트 실행

### 전체 테스트 실행

```bash
# 모든 모듈 테스트
./test-workshop.sh
```

### 테스트 결과 예시

```
[INFO] ========================================
[INFO] AKS Workshop 테스트 시작
[INFO] ========================================
[INFO] 환경 변수 확인 완료: CLUSTER=istio-addon-lab, RESOURCE_GROUP=gmarket-istio-lab
[INFO] 클러스터 연결 확인 완료
[INFO] =========================================
[INFO] 기본 Deployment 테스트
[INFO] =========================================
[INFO] 테스트 네임스페이스 생성: test-basic-deploy
[INFO] Deployment 생성...
[INFO] ✓ Deployment 테스트 성공
...
[INFO] ========================================
[INFO] 테스트 완료
[INFO] ========================================
[INFO] ✓ 모든 테스트 통과!
```

## 모듈별 수동 테스트

### Kubernetes 기초

#### 1. Basic Deployment

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
        image: nginx:1.21
        ports:
        - containerPort: 80
EOF

# 확인
kubectl get deployments -n test-deploy
kubectl get pods -n test-deploy

# 정리
kubectl delete namespace test-deploy
```

#### 2. Service

```bash
kubectl create namespace test-service

# Deployment 및 Service 생성
kubectl apply -n test-service -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.21
---
apiVersion: v1
kind: Service
metadata:
  name: web-service
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 80
EOF

# 확인
kubectl get svc -n test-service
kubectl get pods -n test-service

# 외부 IP로 접근 테스트 (1-2분 대기)
EXTERNAL_IP=$(kubectl get svc web-service -n test-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$EXTERNAL_IP

# 정리
kubectl delete namespace test-service
```

#### 3. ConfigMap

```bash
kubectl create namespace test-config

# ConfigMap 생성
kubectl create configmap app-config \
  --from-literal=app.name=MyApp \
  --from-literal=app.env=production \
  -n test-config

# Pod에서 사용
kubectl apply -n test-config -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: config-test-pod
spec:
  containers:
  - name: test
    image: busybox
    command: ['sh', '-c', 'env && sleep 3600']
    env:
    - name: APP_NAME
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: app.name
EOF

# 확인
sleep 5
kubectl logs config-test-pod -n test-config | grep APP_NAME

# 정리
kubectl delete namespace test-config
```

### 고급 Kubernetes

#### 1. Volumes

```bash
kubectl create namespace test-volume

# emptyDir 볼륨 테스트
kubectl apply -n test-volume -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: volume-test
spec:
  containers:
  - name: writer
    image: busybox
    command: ['sh', '-c', 'echo "Hello from writer" > /data/message && sleep 3600']
    volumeMounts:
    - name: shared-data
      mountPath: /data
  - name: reader
    image: busybox
    command: ['sh', '-c', 'sleep 10 && cat /data/message && sleep 3600']
    volumeMounts:
    - name: shared-data
      mountPath: /data
  volumes:
  - name: shared-data
    emptyDir: {}
EOF

# 확인
sleep 15
kubectl logs volume-test -c reader -n test-volume

# 정리
kubectl delete namespace test-volume
```

#### 2. Probes

```bash
kubectl create namespace test-probes

kubectl apply -n test-probes -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: probe-test
spec:
  containers:
  - name: nginx
    image: nginx:1.21
    livenessProbe:
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 3
      periodSeconds: 5
    readinessProbe:
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 3
      periodSeconds: 5
EOF

# 확인
sleep 10
kubectl get pod probe-test -n test-probes
kubectl describe pod probe-test -n test-probes | grep -A 10 "Liveness\|Readiness"

# 정리
kubectl delete namespace test-probes
```

### Pod 스케줄링

#### 1. Node Selector

```bash
kubectl create namespace test-scheduling

kubectl apply -n test-scheduling -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: node-selector-test
spec:
  nodeSelector:
    kubernetes.io/os: linux
  containers:
  - name: nginx
    image: nginx:1.21
EOF

# 확인
kubectl get pod node-selector-test -n test-scheduling -o wide

# 정리
kubectl delete namespace test-scheduling
```

### 리소스 관리

#### 1. Resource Requests/Limits

```bash
kubectl create namespace test-resources

kubectl apply -n test-resources -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: resource-test
spec:
  containers:
  - name: nginx
    image: nginx:1.21
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
      limits:
        memory: "128Mi"
        cpu: "200m"
EOF

# 확인
kubectl get pod resource-test -n test-resources
kubectl describe pod resource-test -n test-resources | grep -A 10 "Requests\|Limits"

# 정리
kubectl delete namespace test-resources
```

## 리소스 정리

### 테스트 리소스만 정리

```bash
./cleanup-workshop.sh --test
```

### Bookinfo 정리

```bash
./cleanup-workshop.sh --bookinfo
```

### Istio 리소스 정리

```bash
./cleanup-workshop.sh --istio
```

### 모든 리소스 정리

```bash
./cleanup-workshop.sh --all
```

### 클러스터 완전 삭제

```bash
DELETE_CLUSTER=true ./cleanup-workshop.sh --delete-cluster
```

## 문제 해결

### 테스트 실패 시

1. **Pod가 Pending 상태**
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   ```
   - 노드 리소스 부족 확인
   - PVC 바인딩 확인

2. **ImagePullBackOff 오류**
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   ```
   - 이미지 이름 및 태그 확인
   - 네트워크 연결 확인

3. **Service 연결 실패**
   ```bash
   kubectl get endpoints <service-name> -n <namespace>
   ```
   - Selector 확인
   - Pod 레이블 확인

### 로그 확인

```bash
# Pod 로그
kubectl logs <pod-name> -n <namespace>

# 특정 컨테이너 로그
kubectl logs <pod-name> -c <container-name> -n <namespace>

# 실시간 로그
kubectl logs -f <pod-name> -n <namespace>

# 이전 컨테이너 로그
kubectl logs <pod-name> --previous -n <namespace>
```

### 리소스 상태 확인

```bash
# 모든 리소스
kubectl get all -n <namespace>

# 특정 리소스 상세 정보
kubectl describe <resource-type> <resource-name> -n <namespace>

# YAML 확인
kubectl get <resource-type> <resource-name> -n <namespace> -o yaml
```

## 검증 체크리스트

- [ ] 모든 Deployment가 정상적으로 생성되고 Pod가 Running 상태인가?
- [ ] Service가 올바르게 생성되고 Endpoint가 연결되었는가?
- [ ] ConfigMap과 Secret이 Pod에서 정상적으로 사용되는가?
- [ ] 볼륨이 올바르게 마운트되고 데이터가 공유되는가?
- [ ] Probe가 설정되고 헬스 체크가 작동하는가?
- [ ] 스케줄링 제약 조건이 올바르게 적용되는가?
- [ ] 리소스 제한이 설정되고 적용되는가?
- [ ] 테스트 후 모든 리소스가 정리되는가?

## 다음 단계

모든 테스트가 통과하면:

1. Istio 실습 진행 ([Hands-on Labs](https://dotnetpower.github.io/aks-workshop/category/hands-on-labs))
2. 모니터링 도구 설치 및 활용
3. 프로덕션 환경을 위한 베스트 프랙티스 적용
