# Taint와 Toleration

Taint와 Toleration을 활용하여 특정 워크로드를 특정 노드에 격리하거나 전용으로 할당하는 방법을 학습합니다.

## Taint와 Toleration이란?

* **Taint**: 노드에 설정하는 "오염" 마크로, 특정 Pod만 스케줄링되도록 제한
* **Toleration**: Pod에 설정하는 "허용" 마크로, Taint가 있는 노드에도 스케줄링 가능

### Taint Effect 종류

| Effect | 설명 |
|--------|------|
| **NoSchedule** | Toleration이 없는 Pod는 스케줄링되지 않음 |
| **PreferNoSchedule** | 가능하면 스케줄링하지 않음 (소프트 제약) |
| **NoExecute** | 실행 중인 Pod도 제거 (Toleration 없으면) |

## 실습 1: 기본 Taint와 Toleration

### 1. 초기 워크로드 생성

```yaml title="workload-1.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-1
  labels:
    scope: demo
spec:
  replicas: 12
  selector:
    matchLabels:
      app: nginx-1
  template:
    metadata:
      labels:
        app: nginx-1
        color: lime
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
```

```yaml title="workload-2.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-2
  labels:
    scope: demo
spec:
  replicas: 12
  selector:
    matchLabels:
      app: nginx-2
  template:
    metadata:
      labels:
        app: nginx-2
        color: orange
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
```

```yaml title="workload-3.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-3
  labels:
    scope: demo
spec:
  replicas: 12
  selector:
    matchLabels:
      app: nginx-3
  template:
    metadata:
      labels:
        app: nginx-3
        color: aqua
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
```

```bash
kubectl apply -f workload-1.yaml -f workload-2.yaml -f workload-3.yaml

# Pod 분산 확인
kubectl get pods -o wide
```

### 2. 노드에 레이블 추가

특정 노드를 선택합니다:

```bash
# 노드 목록 확인
kubectl get nodes

# 노드 선택 (예: aks-nodepool1-12345678-vmss000000)
export SELECTED_NODE="<node-name>"

# 레이블 추가
kubectl label node $SELECTED_NODE color=lime
kubectl label node $SELECTED_NODE allowedprocess=gpu

# 레이블 확인
kubectl get node $SELECTED_NODE --show-labels
```

### 3. NodeSelector 추가

workload-1에 NodeSelector를 추가합니다:

```yaml title="workload-1-node-selector.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-1
  labels:
    scope: demo  
spec:
  replicas: 12
  selector:
    matchLabels:
      app: nginx-1
  template:
    metadata:
      labels:
        app: nginx-1
        color: lime
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
      nodeSelector:
        color: lime
        allowedprocess: gpu
```

```bash
kubectl apply -f workload-1-node-selector.yaml

# workload-1의 Pod가 선택한 노드로 이동하는 것을 확인
kubectl get pods -l app=nginx-1 -o wide
```

### 4. Taint 추가

```bash
# NoSchedule Taint 추가
kubectl taint node $SELECTED_NODE onlyprocess=gpu:NoSchedule

# Taint 확인
kubectl describe node $SELECTED_NODE | grep Taint
```

### 5. Pod 삭제 및 재스케줄링 확인

```bash
# 선택한 노드의 모든 Pod 삭제
kubectl delete pods --field-selector=spec.nodeName=$SELECTED_NODE

# Pod 상태 확인
kubectl get pods -o wide

# workload-1 Pod들이 Pending 상태인지 확인
kubectl get pods -l app=nginx-1

# 이벤트 확인
kubectl describe pod -l app=nginx-1 | grep -A 5 Events
```

Taint 때문에 workload-1 Pod들도 스케줄링되지 않습니다.

### 6. Toleration 추가

```yaml title="workload-1-toleration.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-1
  labels:
    scope: demo  
spec:
  replicas: 12
  selector:
    matchLabels:
      app: nginx-1
  template:
    metadata:
      labels:
        app: nginx-1
        color: lime
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
      nodeSelector:
        color: lime
        allowedprocess: gpu
      tolerations:
      - key: "onlyprocess"
        operator: "Equal"
        value: "gpu"
        effect: "NoSchedule"
```

```bash
kubectl apply -f workload-1-toleration.yaml

# workload-1 Pod만 선택한 노드에 스케줄링됨
kubectl get pods -o wide
```

## 실습 2: NoExecute Effect

### 1. NoExecute Taint 추가

```bash
# 먼저 NoSchedule Taint 제거
kubectl taint node $SELECTED_NODE onlyprocess-

# NoExecute Taint 추가
kubectl taint node $SELECTED_NODE onlyprocess=gpu:NoExecute

# 즉시 Toleration이 없는 Pod들이 제거됨
kubectl get pods -o wide -w
```

### 2. Toleration에 tolerationSeconds 추가

```yaml title="workload-1-toleration-seconds.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-1
spec:
  replicas: 12
  selector:
    matchLabels:
      app: nginx-1
  template:
    metadata:
      labels:
        app: nginx-1
        color: lime
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
      nodeSelector:
        color: lime
      tolerations:
      - key: "onlyprocess"
        operator: "Equal"
        value: "gpu"
        effect: "NoExecute"
        tolerationSeconds: 60
```

60초 후에 Pod가 제거됩니다.

## 실습 3: AKS 시스템 노드 풀

AKS는 시스템 노드 풀에 자동으로 Taint를 설정합니다:

```bash
# 시스템 노드 풀 생성
az aks nodepool add \
  --resource-group myResourceGroup \
  --cluster-name myAKSCluster \
  --name systempool \
  --node-count 3 \
  --mode System

# 시스템 노드 Taint 확인
kubectl get nodes -l agentpool=systempool -o json | jq '.items[].spec.taints'
```

시스템 Pod만 배치되도록 Toleration 설정:

```yaml
tolerations:
- key: CriticalAddonsOnly
  operator: Exists
  effect: NoSchedule
```

## 실습 4: GPU 노드 전용 할당

### 1. GPU 노드 풀 생성

```bash
az aks nodepool add \
  --resource-group myResourceGroup \
  --cluster-name myAKSCluster \
  --name gpupool \
  --node-count 1 \
  --node-vm-size Standard_NC6 \
  --node-taints sku=gpu:NoSchedule
```

### 2. GPU 워크로드 배포

```yaml title="gpu-workload.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-workload
spec:
  replicas: 2
  selector:
    matchLabels:
      app: gpu-app
  template:
    metadata:
      labels:
        app: gpu-app
    spec:
      tolerations:
      - key: "sku"
        operator: "Equal"
        value: "gpu"
        effect: "NoSchedule"
      nodeSelector:
        agentpool: gpupool
      containers:
      - name: gpu-container
        image: nvidia/cuda:11.0-base
        resources:
          limits:
            nvidia.com/gpu: 1
```

```bash
kubectl apply -f gpu-workload.yaml
```

## 정리

```bash
# Deployment 삭제
kubectl delete deployment -l scope=demo
kubectl delete deployment gpu-workload

# Taint 제거
kubectl taint node $SELECTED_NODE onlyprocess-

# 레이블 제거
kubectl label node $SELECTED_NODE color-
kubectl label node $SELECTED_NODE allowedprocess-
```

## 핵심 정리

* **Taint**: 노드에 제약을 추가하여 특정 Pod만 허용
* **Toleration**: Pod가 Taint가 있는 노드에 스케줄링되도록 허용
* **NoSchedule**: 신규 Pod 스케줄링 방지
* **NoExecute**: 실행 중인 Pod도 제거
* **PreferNoSchedule**: 소프트 제약
* **전용 노드**: GPU, 고성능 워크로드 격리

## 실습 과제

1. PreferNoSchedule Effect를 사용하여 소프트 제약을 설정하고 동작을 확인해보세요.
2. 여러 개의 Taint를 노드에 추가하고, 모든 Taint에 대한 Toleration이 필요한지 확인해보세요.
3. tolerationSeconds를 사용하여 일정 시간 후 Pod가 제거되는 것을 확인해보세요.

## 다음 단계

[Topology Spread Constraints](./topology-spread)에서 토폴로지 기반 Pod 분산 방법을 학습합니다.
