# Anti-Affinity와 StatefulSet

Pod Anti-Affinity와 StatefulSet을 활용하여 고가용성을 보장하는 분산 배치 전략을 학습합니다.

## Pod Anti-Affinity란?

Pod Anti-Affinity는 특정 Pod들이 서로 다른 노드에 배치되도록 제어하는 메커니즘입니다. 고가용성이 중요한 애플리케이션에서 단일 노드 장애로부터 보호하는 데 사용됩니다.

### Anti-Affinity 유형

1. **requiredDuringSchedulingIgnoredDuringExecution**: 반드시 다른 노드에 배치 (하드 제약)
2. **preferredDuringSchedulingIgnoredDuringExecution**: 가능하면 다른 노드에 배치 (소프트 제약)

## StatefulSet과 Anti-Affinity

StatefulSet은 상태를 가진 애플리케이션(데이터베이스, 메시징 시스템 등)을 관리하는 리소스입니다. Anti-Affinity와 결합하면 각 인스턴스를 서로 다른 노드에 배치하여 고가용성을 확보할 수 있습니다.

## 실습 1: Anti-Affinity StatefulSet

### 1. StatefulSet과 Service 생성

```yaml title="pvc-ss.yaml"
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: pvc-pod-ss
spec:
  replicas: 2
  serviceName: pvc-pod-svc
  selector:
    matchLabels:
      target: pvc-ss-pod       
  template:
    metadata:
      labels:
        target: pvc-ss-pod
        color: aqua
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 250m
            memory: 256Mi
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: target
                operator: In
                values:
                - pvc-ss-pod
            topologyKey: "kubernetes.io/hostname"
---
apiVersion: v1
kind: Service
metadata:
  name: pvc-pod-svc
spec:
  ports:
  - port: 80
    targetPort: 80
  clusterIP: None
  selector:
    target: pvc-ss-pod
```

```bash
kubectl apply -f pvc-ss.yaml
```

### 2. 배포 확인

```bash
# StatefulSet 확인
kubectl get statefulset

# Pod와 노드 확인
kubectl get pods -l target=pvc-ss-pod -o wide

# 각 Pod가 다른 노드에 배치되었는지 확인
kubectl get pods -l target=pvc-ss-pod -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName
```

### 3. 스케일 증가

```bash
# 3개로 증가
kubectl scale --replicas=3 statefulset/pvc-pod-ss

# Pod 상태 확인
kubectl get pods -l target=pvc-ss-pod -o wide
```

노드가 2개뿐이면 세 번째 Pod는 Pending 상태가 됩니다.

### 4. 이벤트 확인

```bash
# Pending Pod 상세 정보
kubectl describe pod pvc-pod-ss-2

# Events 섹션에서 스케줄링 실패 이유 확인
# "0/2 nodes are available: 2 node(s) didn't match pod anti-affinity rules"
```

### 5. AKS 클러스터 자동 스케일링

AKS에서 Cluster Autoscaler가 활성화되어 있으면 자동으로 노드가 추가됩니다:

```bash
# 노드 확인
kubectl get nodes

# 몇 분 후 새 노드 추가됨
kubectl get nodes -w

# Pod가 새 노드에 스케줄링됨
kubectl get pods -l target=pvc-ss-pod -o wide
```

## 실습 2: VolumeClaimTemplate과 Anti-Affinity

StatefulSet은 각 Pod에 고유한 PVC를 자동 생성할 수 있습니다:

```yaml title="statefulset-pvc.yaml"
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: data-ss
spec:
  serviceName: data-svc
  replicas: 3
  selector:
    matchLabels:
      app: data-app
  template:
    metadata:
      labels:
        app: data-app
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - data-app
            topologyKey: "kubernetes.io/hostname"
      containers:
      - name: app
        image: nginx:1.27
        volumeMounts:
        - name: data
          mountPath: /mnt/data
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 250m
            memory: 256Mi
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: managed-csi
      resources:
        requests:
          storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: data-svc
spec:
  ports:
  - port: 80
  clusterIP: None
  selector:
    app: data-app
```

```bash
kubectl apply -f statefulset-pvc.yaml

# PVC 자동 생성 확인
kubectl get pvc

# 각 Pod가 고유한 PVC를 가짐
kubectl get pvc -l app=data-app
```

## 실습 3: Topology Spread와 함께 사용

### 가용성 영역 기반 분산

```yaml title="statefulset-zone-spread.yaml"
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ha-statefulset
spec:
  serviceName: ha-svc
  replicas: 6
  selector:
    matchLabels:
      app: ha-app
  template:
    metadata:
      labels:
        app: ha-app
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: ha-app
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - ha-app
              topologyKey: "kubernetes.io/hostname"
      containers:
      - name: app
        image: nginx:1.27
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: ha-svc
spec:
  ports:
  - port: 80
  clusterIP: None
  selector:
    app: ha-app
```

```bash
kubectl apply -f statefulset-zone-spread.yaml

# Zone별 분산 확인
kubectl get pods -l app=ha-app -o custom-columns=\
NAME:.metadata.name,\
NODE:.spec.nodeName,\
ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone
```

## AKS에서 Anti-Affinity 활용

### 다중 가용성 영역 노드 풀

```bash
# 3개 가용성 영역에 노드 풀 생성
az aks nodepool add \
  --resource-group myResourceGroup \
  --cluster-name myAKSCluster \
  --name multizone \
  --node-count 3 \
  --zones 1 2 3 \
  --enable-cluster-autoscaler \
  --min-count 3 \
  --max-count 9
```

## 정리

```bash
kubectl delete statefulset pvc-pod-ss data-ss ha-statefulset
kubectl delete service pvc-pod-svc data-svc ha-svc
kubectl delete pvc --all
```

## 핵심 정리

* **Pod Anti-Affinity**: Pod를 서로 다른 노드에 분산 배치
* **StatefulSet**: 상태를 가진 애플리케이션의 순서 있는 배포
* **VolumeClaimTemplate**: 각 Pod에 고유한 PVC 자동 생성
* **Required Anti-Affinity**: 노드가 부족하면 Pod가 Pending 상태
* **Cluster Autoscaler**: 자동으로 노드를 추가하여 해결
* **고가용성**: 노드/Zone 장애로부터 보호

## 실습 과제

1. 5개의 replica를 가진 StatefulSet을 생성하고, Cluster Autoscaler가 노드를 추가하는 과정을 관찰해보세요.
2. Zone Anti-Affinity를 사용하여 각 가용성 영역에 최소 1개의 Pod가 배치되도록 설정해보세요.
3. Preferred Anti-Affinity를 사용하여 소프트 제약을 적용하고 동작 차이를 확인해보세요.

## 다음 단계

[Taint와 Toleration](./taint-tolerations)에서 노드 격리 및 전용 할당 방법을 학습합니다.
