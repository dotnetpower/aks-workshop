# 리소스 관리

Kubernetes의 리소스 Requests/Limits, LimitRange, ResourceQuota를 이해하고 실습합니다.

## 리소스 관리 개요

Kubernetes는 다음 메커니즘으로 리소스를 관리합니다:

1. **Resource Requests/Limits**: Pod/Container 레벨 리소스 설정
2. **LimitRange**: Namespace의 기본값 및 최소/최대 제한
3. **ResourceQuota**: Namespace의 총 리소스 할당량

## 실습 1: Resource Requests/Limits

### 1. 리소스 설정 없는 워크로드 생성

```yaml title="workload1-dep.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload1-dep
  labels:
    app: demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: workload1
  template:
    metadata:
      labels:
        app: workload1
        color: lime
    spec:
      containers:
      - name: nginx
        image: nginx:1.17
        ports:
        - containerPort: 80
```

```yaml title="workload2-dep.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload2-dep
  labels:
    app: demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: workload2
  template:
    metadata:
      labels:
        app: workload2
        color: orange
    spec:
      containers:
      - name: nginx
        image: nginx:1.17
        ports:
        - containerPort: 80
```

```yaml title="workload3-dep.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload3-dep
  labels:
    app: demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: workload3
  template:
    metadata:
      labels:
        app: workload3
        color: aqua
    spec:
      containers:
      - name: nginx
        image: nginx:1.17
        ports:
        - containerPort: 80
```

```yaml title="workload4-dep.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload4-dep
  labels:
    app: demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: workload4
  template:
    metadata:
      labels:
        app: workload4
        color: pink
    spec:
      containers:
      - name: nginx
        image: nginx:1.17
        ports:
        - containerPort: 80
```

```bash
kubectl apply -f workload1-dep.yaml \
  -f workload2-dep.yaml \
  -f workload3-dep.yaml \
  -f workload4-dep.yaml

# Pod 리소스 확인
kubectl describe pods -l app=workload1
```

Requests/Limits가 설정되지 않은 것을 확인할 수 있습니다 (BestEffort QoS).

## 실습 2: LimitRange 적용

### 1. LimitRange 생성

```yaml title="namespace-limit-range.yaml"
apiVersion: v1
kind: LimitRange
metadata:
  name: namespace-limit-range
  labels:
    app: demo  
spec:
  limits:
  - default:              # 기본 Limit (설정 안 했을 때)
      cpu: 200m
      memory: 256Mi
    defaultRequest:       # 기본 Request (설정 안 했을 때)
      cpu: 100m
      memory: 128Mi
    max:                  # 최대 Limit
      cpu: 1
      memory: 1Gi       
    min:                  # 최소 Request
      cpu: 50m
      memory: 64Mi       
    type: Container
```

```bash
kubectl apply -f namespace-limit-range.yaml

# LimitRange 확인
kubectl describe limitrange namespace-limit-range
```

### 2. 기존 Pod 업데이트

LimitRange는 새로운 Pod에만 적용됩니다. 기존 Pod를 재생성해야 합니다:

```bash
# 이미지를 변경하여 새 ReplicaSet 생성
kubectl set image deployment/workload1-dep nginx=nginx:1.18
kubectl set image deployment/workload2-dep nginx=nginx:1.18
kubectl set image deployment/workload3-dep nginx=nginx:1.18
kubectl set image deployment/workload4-dep nginx=nginx:1.18

# Pod 확인
kubectl get pods

# 리소스 확인
kubectl describe pod -l app=workload1 | grep -A 5 "Requests:"
```

이제 모든 Pod에 기본 Requests/Limits가 적용됩니다.

### 3. 실제 리소스 사용량 확인

```bash
# Metrics Server 확인
kubectl top pods

# 특정 워크로드
kubectl top pods -l app=workload1
```

## 실습 3: ResourceQuota 적용

### 1. ResourceQuota 생성

```yaml title="namespace-resource-quotas.yaml"
apiVersion: v1
kind: ResourceQuota
metadata:
  name: namespace-resource-quota-1
  labels:
    app: demo
spec:
  hard:
    requests.cpu: "1200m"      # 총 CPU Request 제한
    limits.cpu: "2000m"        # 총 CPU Limit 제한
    requests.memory: 1.25Gi    # 총 Memory Request 제한
    limits.memory: 2.5Gi       # 총 Memory Limit 제한
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: namespace-resource-quota-2
  labels:
    app: demo
spec:
  hard:
    pods: "10"                           # 최대 Pod 개수
    configmaps: "10"                     # 최대 ConfigMap 개수
    secrets: "40"                        # 최대 Secret 개수
    persistentvolumeclaims: "4"          # 최대 PVC 개수
    services: "10"                       # 최대 Service 개수
    services.loadbalancers: "2"          # 최대 LoadBalancer 개수
```

```bash
kubectl apply -f namespace-resource-quotas.yaml

# ResourceQuota 확인
kubectl describe resourcequota
```

### 2. Quota 초과 테스트

```bash
# 이미지 변경으로 재배포 시도
kubectl set image deployment/workload1-dep nginx=nginx:1.19
kubectl set image deployment/workload2-dep nginx=nginx:1.19
kubectl set image deployment/workload3-dep nginx=nginx:1.19
kubectl set image deployment/workload4-dep nginx=nginx:1.19

# ReplicaSet 이벤트 확인
kubectl describe replicaset -l app=workload1

# "exceeded quota" 메시지 확인
```

Memory Limit이 Quota를 초과하여 업데이트가 실패합니다.

### 3. Quota 증가

```yaml title="namespace-resource-quotas-slight.yaml"
apiVersion: v1
kind: ResourceQuota
metadata:
  name: namespace-resource-quota-1
  labels:
    app: demo
spec:
  hard:
    requests.cpu: "1400m"
    limits.cpu: "2400m"
    requests.memory: 1.5Gi
    limits.memory: 3Gi
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: namespace-resource-quota-2
  labels:
    app: demo
spec:
  hard:
    pods: "15"
    configmaps: "10"
    secrets: "40"
    persistentvolumeclaims: "4"
    services: "10"
    services.loadbalancers: "2"
```

```bash
kubectl apply -f namespace-resource-quotas-slight.yaml

# 상태 관찰
kubectl get pods -w
```

ReplicaSet이 조금씩 Pod를 교체하기 시작합니다 (여유 공간이 생기면).

### 4. Quota 대폭 증가

```yaml title="namespace-resource-quotas-double.yaml"
apiVersion: v1
kind: ResourceQuota
metadata:
  name: namespace-resource-quota-1
  labels:
    app: demo
spec:
  hard:
    requests.cpu: "2400m"
    limits.cpu: "4000m"
    requests.memory: 2.5Gi
    limits.memory: 5Gi
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: namespace-resource-quota-2
  labels:
    app: demo
spec:
  hard:
    pods: "30"
    configmaps: "20"
    secrets: "50"
    persistentvolumeclaims: "10"
    services: "20"
    services.loadbalancers: "5"
```

```bash
kubectl apply -f namespace-resource-quotas-double.yaml

# 이미지 변경
kubectl set image deployment/workload1-dep nginx=nginx:1.20
kubectl set image deployment/workload2-dep nginx=nginx:1.20
kubectl set image deployment/workload3-dep nginx=nginx:1.20
kubectl set image deployment/workload4-dep nginx=nginx:1.20

# 빠르게 업데이트됨
kubectl get pods -w
```

이제 충분한 Quota가 있어 모든 Pod가 동시에 업데이트됩니다.

## 실습 4: QoS 클래스

### Guaranteed QoS

```yaml title="guaranteed-pod.yaml"
apiVersion: v1
kind: Pod
metadata:
  name: guaranteed-pod
spec:
  containers:
  - name: nginx
    image: nginx:1.18
    resources:
      requests:
        cpu: 200m
        memory: 256Mi
      limits:
        cpu: 200m        # Request = Limit
        memory: 256Mi    # Request = Limit
```

```bash
kubectl apply -f guaranteed-pod.yaml

# QoS 확인
kubectl get pod guaranteed-pod -o jsonpath='{.status.qosClass}'
# Guaranteed
```

### Burstable QoS

```yaml title="burstable-pod.yaml"
apiVersion: v1
kind: Pod
metadata:
  name: burstable-pod
spec:
  containers:
  - name: nginx
    image: nginx:1.18
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m        # Request < Limit
        memory: 512Mi    # Request < Limit
```

```bash
kubectl apply -f burstable-pod.yaml

# QoS 확인
kubectl get pod burstable-pod -o jsonpath='{.status.qosClass}'
# Burstable
```

### BestEffort QoS

```yaml title="besteffort-pod.yaml"
apiVersion: v1
kind: Pod
metadata:
  name: besteffort-pod
spec:
  containers:
  - name: nginx
    image: nginx:1.18
    # 리소스 설정 없음
```

```bash
kubectl apply -f besteffort-pod.yaml

# QoS 확인
kubectl get pod besteffort-pod -o jsonpath='{.status.qosClass}'
# BestEffort
```

## 정리

```bash
kubectl delete deployment -l app=demo
kubectl delete limitrange namespace-limit-range
kubectl delete resourcequota -l app=demo
kubectl delete pod guaranteed-pod burstable-pod besteffort-pod
```

## 핵심 정리

* **Requests**: 보장된 리소스, 스케줄링에 사용
* **Limits**: 최대 사용 가능 리소스, 초과 시 제한
* **LimitRange**: Namespace의 기본값 및 최소/최대 제한
* **ResourceQuota**: Namespace의 총 할당량
* **QoS 클래스**: Guaranteed > Burstable > BestEffort
* **리소스 부족**: QoS 낮은 순서로 Pod 제거

## 실습 과제

1. CPU Limit을 초과하는 워크로드를 생성하고 Throttling을 관찰해보세요.
2. Memory Limit을 초과하는 워크로드를 생성하고 OOMKilled를 확인해보세요.
3. 여러 Namespace를 생성하고 각각 다른 ResourceQuota를 적용해보세요.
4. LimitRange의 max/min 값을 위반하는 Pod를 생성하고 에러 메시지를 확인해보세요.

## 다음 단계

[Horizontal Pod Autoscaler](./hpa)에서 CPU/Memory 기반 자동 스케일링을 학습합니다.
