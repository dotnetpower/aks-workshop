# Node Affinity와 Volume

Node Affinity와 Volume을 함께 사용하여 스토리지 제약이 있는 워크로드를 효율적으로 배치하는 방법을 학습합니다.

## Node Affinity란?

Node Affinity는 Pod가 특정 노드에 스케줄링되도록 제어하는 메커니즘입니다.

### Affinity 유형

1. **requiredDuringSchedulingIgnoredDuringExecution**: 반드시 만족해야 함 (하드 제약)
2. **preferredDuringSchedulingIgnoredDuringExecution**: 가능하면 만족 (소프트 제약)

## Pod Affinity와 Volume의 관계

Azure Disk와 같은 ReadWriteOnce(RWO) 볼륨은 하나의 노드에만 연결될 수 있습니다. Pod Affinity를 사용하면 같은 볼륨을 사용하는 Pod들을 동일 노드에 배치할 수 있습니다.

## 실습 1: PVC와 Pod Affinity

### 1. PersistentVolumeClaim 생성

```yaml title="pvc.yaml"
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-azure-disk
spec:
  storageClassName: default  
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 8Gi
```

```bash
kubectl apply -f pvc.yaml
```

### 2. Required Pod Affinity 적용

동일한 PVC를 사용하는 Pod들을 같은 노드에 배치합니다:

```yaml title="pvc-dep-required.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pvc-pod-dep
spec:
  replicas: 6
  selector:
    matchLabels:
      target: pvc-pod       
  template:
    metadata:
      labels:
        target: pvc-pod
        color: LightSalmon
    spec:
      containers:
      - name: nginx
        image: nginx:1.18
        ports:
        - containerPort: 80
        resources: 
          requests:
            cpu: 80m
            memory: 128Mi
          limits:
            cpu: 250m
            memory: 256Mi   
        volumeMounts:
        - mountPath: "/mnt/data"
          name: mypvc
      volumes:
      - name: mypvc
        persistentVolumeClaim:
          claimName: pvc-azure-disk   
      affinity:
        podAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: target
                operator: In
                values:
                - pvc-pod
            topologyKey: "kubernetes.io/hostname"
```

```bash
kubectl apply -f pvc-dep-required.yaml
```

### 3. 배포 확인

```bash
# Pod와 노드 확인
kubectl get pods -o wide

# 모든 Pod가 동일 노드에 있는지 확인
kubectl get pods -l target=pvc-pod -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName
```

### 4. 스케일 테스트

```bash
# 12개로 증가
kubectl scale --replicas=12 deployment/pvc-pod-dep

# 노드 확인 - 여전히 같은 노드
kubectl get pods -l target=pvc-pod -o wide

# 24개로 증가
kubectl scale --replicas=24 deployment/pvc-pod-dep

# 일부 Pod는 Pending 상태
kubectl get pods -l target=pvc-pod
```

노드에 더 이상 리소스가 없으면 다른 노드에 여유가 있어도 Pod가 Pending 상태로 남습니다.

## 실습 2: Preferred Affinity로 변경

### 1. Preferred Affinity 적용

```yaml title="pvc-dep-preferred.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pvc-pod-dep
spec:
  replicas: 24
  selector:
    matchLabels:
      target: pvc-pod       
  template:
    metadata:
      labels:
        target: pvc-pod
        color: LightSalmon
    spec:
      containers:
      - name: nginx
        image: nginx:1.18
        ports:
        - containerPort: 80
        resources: 
          requests:
            cpu: 80m
            memory: 128Mi
          limits:
            cpu: 250m
            memory: 256Mi   
        volumeMounts:
        - mountPath: "/mnt/data"
          name: mypvc
      volumes:
      - name: mypvc
        persistentVolumeClaim:
          claimName: pvc-azure-disk   
      affinity:
        podAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: target
                  operator: In
                  values:
                  - pvc-pod
              topologyKey: "kubernetes.io/hostname"
```

```bash
kubectl apply -f pvc-dep-preferred.yaml
```

### 2. 결과 확인

```bash
# Pending Pod들이 다른 노드에 스케줄링됨
kubectl get pods -l target=pvc-pod -o wide

# 하지만 볼륨 마운트 실패
kubectl describe pod <pod-name>
```

다른 노드의 Pod들은 볼륨을 마운트할 수 없어 에러 상태가 됩니다.

## Zone-aware 스토리지

### AKS에서 가용성 영역 활용

```yaml title="pvc-zonal.yaml"
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-azure-disk-zonal
spec:
  storageClassName: managed-csi
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 8Gi
```

### Node Affinity와 Zone 결합

```yaml title="deployment-zone-affinity.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zonal-workload
spec:
  replicas: 3
  selector:
    matchLabels:
      app: zonal-app
  template:
    metadata:
      labels:
        app: zonal-app
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: topology.kubernetes.io/zone
                operator: In
                values:
                - koreacentral-1
      containers:
      - name: app
        image: nginx:1.18
        volumeMounts:
        - name: data
          mountPath: /mnt/data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: pvc-azure-disk-zonal
```

```bash
kubectl apply -f pvc-zonal.yaml
kubectl apply -f deployment-zone-affinity.yaml

# Zone 확인
kubectl get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,ZONE:.spec.nodeSelector
```

## 정리

```bash
kubectl delete deployment pvc-pod-dep
kubectl delete pvc pvc-azure-disk
kubectl delete pvc pvc-azure-disk-zonal
kubectl delete deployment zonal-workload
```

## 핵심 정리

* **Pod Affinity**: 같은 볼륨을 사용하는 Pod를 동일 노드에 배치
* **Required Affinity**: 필수 조건, 만족하지 못하면 Pending
* **Preferred Affinity**: 선호 조건, 만족하지 못해도 다른 노드에 배치
* **RWO Volume**: 하나의 노드에만 연결 가능
* **Zone-aware Storage**: 가용성 영역을 고려한 스토리지 배치

## 실습 과제

1. ReadWriteMany(RWX)를 지원하는 Azure Files PVC를 생성하고, 여러 노드에 Pod를 분산 배치해보세요.
2. Node Affinity를 사용하여 특정 노드 풀(예: GPU 노드)에만 Pod를 배치해보세요.
3. Preferred Affinity의 weight 값을 다르게 설정하여 스케줄링 우선순위를 조정해보세요.

## 다음 단계

[Anti-Affinity와 StatefulSet](./anti-affinity-stateful-set)에서 Pod를 분산 배치하는 방법을 학습합니다.
