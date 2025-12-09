# Topology Spread Constraints

Topology Spread Constraints를 사용하여 Pod를 노드, Zone, Region 등 다양한 토폴로지 도메인에 균등하게 분산하는 방법을 학습합니다.

## Topology Spread Constraints란?

Topology Spread Constraints는 Pod를 토폴로지 도메인(노드, Zone 등)에 균등하게 분산시키는 고급 스케줄링 메커니즘입니다. Anti-Affinity보다 세밀한 제어가 가능합니다.

### 주요 필드

* **maxSkew**: 도메인 간 최대 Pod 개수 차이
* **topologyKey**: 분산 기준 (hostname, zone 등)
* **whenUnsatisfiable**: 제약 위반 시 동작
  * `DoNotSchedule`: Pod를 스케줄링하지 않음 (하드 제약)
  * `ScheduleAnyway`: 최대한 분산하되 스케줄링은 허용 (소프트 제약)

## 실습 1: 노드 레벨 분산

### 1. 기본 Topology Spread

```yaml title="workload.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload
  labels:
    scope: demo
spec:  
  replicas: 3
  selector:
    matchLabels:
      app: nginx-1
  template:
    metadata:
      labels:
        app: nginx-1
        color: lime
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: nginx-1
      containers:
      - name: nginx
        image: nginx:1.18
        ports:
        - containerPort: 80
        resources: 
          requests:
            cpu: 100m
            memory: 128Mi              
          limits:
            cpu: 250m
            memory: 256Mi
```

```bash
kubectl apply -f workload.yaml

# Pod 분산 확인
kubectl get pods -l app=nginx-1 -o wide

# 노드별 Pod 개수 확인
kubectl get pods -l app=nginx-1 -o json | \
  jq -r '.items[] | .spec.nodeName' | \
  sort | uniq -c
```

3개 노드에 각각 1개씩 균등 분산됩니다.

### 2. Replica 증가

```bash
# 12개로 증가
kubectl scale --replicas=12 deployment/workload

# 노드별 Pod 개수 확인
kubectl get pods -l app=nginx-1 -o json | \
  jq -r '.items[] | .spec.nodeName' | \
  sort | uniq -c
```

maxSkew=1이므로 각 노드에 4개씩 균등 배치됩니다.

### 3. 더 많은 Replica로 증가

```bash
# 19개로 증가
kubectl scale --replicas=19 deployment/workload

# 노드별 Pod 개수 확인
kubectl get pods -l app=nginx-1 -o json | \
  jq -r '.items[] | .spec.nodeName' | \
  sort | uniq -c
```

3개 노드에 6-7-6 또는 7-6-6으로 분산됩니다 (maxSkew=1 유지).

### 4. Replica 감소

```bash
# 6개로 감소
kubectl scale --replicas=6 deployment/workload

# 노드별 Pod 개수 확인
kubectl get pods -l app=nginx-1 -o json | \
  jq -r '.items[] | .spec.nodeName' | \
  sort | uniq -c
```

**주의**: 삭제 시에는 균등 분산이 보장되지 않습니다. 예를 들어 3-2-1로 분산될 수 있습니다.

### 5. 노드 용량 초과

```bash
# 45개로 증가 (3개 노드로 감당 불가)
kubectl scale --replicas=45 deployment/workload

# Pod 상태 확인
kubectl get pods -l app=nginx-1

# 일부 Pod가 Pending
kubectl get pods -l app=nginx-1 | grep Pending
```

maxSkew=1 때문에 노드에 여유가 있어도 일부 Pod가 Pending 상태로 남습니다.

AKS Cluster Autoscaler가 활성화되어 있으면 새 노드가 추가됩니다:

```bash
# 노드 확인
kubectl get nodes -w
```

새 노드가 추가되면 Pending Pod가 스케줄링되지만, maxSkew 제약으로 인해 완전히 균등하지 않을 수 있습니다.

## 실습 2: maxSkew 조정

### 1. maxSkew를 3으로 변경

```yaml title="patch-maxskew-3.yaml"
spec:
  template:
    spec:
      topologySpreadConstraints:
      - maxSkew: 3
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: nginx-1
```

```bash
kubectl patch deployment workload --patch-file patch-maxskew-3.yaml

# 노드별 Pod 개수 확인
kubectl get pods -l app=nginx-1 -o json | \
  jq -r '.items[] | .spec.nodeName' | \
  sort | uniq -c
```

이제 노드 간 최대 3개 차이까지 허용됩니다.

### 2. ScheduleAnyway로 변경

```yaml title="patch-schedule-anyway.yaml"
spec:
  template:
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: nginx-1
```

```bash
kubectl patch deployment workload --patch-file patch-schedule-anyway.yaml

# 모든 Pod가 스케줄링됨
kubectl get pods -l app=nginx-1
```

maxSkew를 초과해도 스케줄링되지만, 최대한 균등 분산을 시도합니다.

## 실습 3: Zone 레벨 분산

### 1. Zone 기반 분산

```yaml title="workload-zone-spread.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zone-workload
spec:  
  replicas: 9
  selector:
    matchLabels:
      app: zone-app
  template:
    metadata:
      labels:
        app: zone-app
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: zone-app
      containers:
      - name: nginx
        image: nginx:1.18
        resources: 
          requests:
            cpu: 100m
            memory: 128Mi
```

```bash
kubectl apply -f workload-zone-spread.yaml

# Zone별 Pod 개수 확인
kubectl get pods -l app=zone-app -o json | \
  jq -r '.items[] | .metadata.labels."topology.kubernetes.io/zone"' | \
  sort | uniq -c
```

3개 Zone에 각각 3개씩 분산됩니다.

### 2. AKS 다중 Zone 노드 풀 생성

```bash
# 3개 Zone에 노드 풀 생성
az aks nodepool add \
  --resource-group myResourceGroup \
  --cluster-name myAKSCluster \
  --name multizone \
  --node-count 9 \
  --zones 1 2 3 \
  --enable-cluster-autoscaler \
  --min-count 3 \
  --max-count 12

# Zone 확인
kubectl get nodes -L topology.kubernetes.io/zone
```

## 실습 4: 다중 Topology Spread

노드와 Zone 레벨 모두 분산:

```yaml title="multi-topology-spread.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: multi-spread
spec:  
  replicas: 18
  selector:
    matchLabels:
      app: multi-app
  template:
    metadata:
      labels:
        app: multi-app
    spec:
      topologySpreadConstraints:
      # Zone 레벨 분산
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: multi-app
      # 노드 레벨 분산
      - maxSkew: 2
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: multi-app
      containers:
      - name: nginx
        image: nginx:1.18
        resources: 
          requests:
            cpu: 100m
            memory: 128Mi
```

```bash
kubectl apply -f multi-topology-spread.yaml

# Zone별 분산
kubectl get pods -l app=multi-app -o json | \
  jq -r '.items[] | .metadata.labels."topology.kubernetes.io/zone"' | \
  sort | uniq -c

# 노드별 분산
kubectl get pods -l app=multi-app -o json | \
  jq -r '.items[] | .spec.nodeName' | \
  sort | uniq -c
```

## Anti-Affinity vs Topology Spread

| 기능 | Anti-Affinity | Topology Spread |
|------|---------------|-----------------|
| 세밀도 | 전부 또는 전무 | maxSkew로 제어 |
| 균등 분산 | 보장 안 됨 | 보장됨 |
| 다중 토폴로지 | 어려움 | 쉬움 |
| 용도 | 간단한 분산 | 정밀한 분산 제어 |

## 정리

```bash
kubectl delete deployment workload zone-workload multi-spread
```

## 핵심 정리

* **Topology Spread**: Pod를 토폴로지 도메인에 균등 분산
* **maxSkew**: 도메인 간 최대 Pod 개수 차이
* **DoNotSchedule**: 제약 위반 시 스케줄링하지 않음
* **ScheduleAnyway**: 제약 위반해도 스케줄링 (최선 노력)
* **다중 토폴로지**: Zone과 Node 레벨 동시 적용 가능
* **삭제 시**: 균등 분산 보장 안 됨 (스케줄링 시에만)

## 실습 과제

1. maxSkew를 다양한 값(1, 2, 5)으로 변경하며 분산 패턴을 관찰해보세요.
2. Zone과 Region 레벨 Topology Spread를 함께 사용해보세요.
3. whenUnsatisfiable을 DoNotSchedule과 ScheduleAnyway로 변경하며 차이를 확인해보세요.
4. Cluster Autoscaler와 함께 사용하여 자동 노드 추가 시 분산 패턴을 관찰해보세요.

## 다음 단계

이제 [오토스케일링](../autoscaling/intro)에서 워크로드 자동 확장 방법을 학습합니다.
