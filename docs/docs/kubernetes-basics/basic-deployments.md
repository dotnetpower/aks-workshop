# 기본 Deployment

Kubernetes Deployment는 애플리케이션을 배포하고 관리하는 기본 리소스입니다.

## Deployment란?

Deployment는 Pod와 ReplicaSet을 선언적으로 관리하는 리소스로, 다음과 같은 기능을 제공합니다:

* 원하는 상태(Desired State)를 선언하면 자동으로 현재 상태를 맞춤
* 롤링 업데이트를 통한 무중단 배포
* 롤백 기능으로 이전 버전으로 복구
* 스케일링을 통한 Pod 복제본 관리

## 첫 번째 Deployment 생성

### 1. Deployment YAML 작성

```yaml title="workload-dep.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-1-dep
spec:
  replicas: 6
  selector:
    matchLabels:
      app: workload-1
  template:
    metadata:
      labels:
        app: workload-1
        color: lime
    spec:
      containers:
        - name: workload
          image: nginx:1.27
          ports:
            - containerPort: 80
      nodeSelector:
        kubernetes.io/os: linux
```

### 2. Deployment 배포

```bash
kubectl apply -f workload-dep.yaml --record
```

`--record` 플래그는 변경 사항을 히스토리에 기록합니다.

### 3. 배포 상태 확인

```bash
# Deployment 확인
kubectl get deployments

# Pod 확인
kubectl get pods

# ReplicaSet 확인
kubectl get replicasets

# 상세 정보 확인
kubectl describe deployment workload-1-dep
```

## Deployment 업데이트

### 이미지 변경

라벨을 변경하여 새로운 ReplicaSet을 생성합니다:

```yaml title="workload-dep-updated.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-1-dep
spec:
  replicas: 6
  selector:
    matchLabels:
      app: workload-1
  template:
    metadata:
      labels:
        app: workload-1
        color: yellow  # lime에서 yellow로 변경
    spec:
      containers:
        - name: workload
          image: nginx:1.27  # 버전 업데이트
          ports:
            - containerPort: 80
      nodeSelector:
        kubernetes.io/os: linux
```

```bash
kubectl apply -f workload-dep-updated.yaml --record
```

### 롤링 업데이트 관찰

```bash
# 실시간으로 업데이트 상태 확인
kubectl rollout status deployment/workload-1-dep

# ReplicaSet 확인 (이전 버전과 새 버전이 모두 보임)
kubectl get rs -w
```

## 배포 전략

### Rolling Update (기본값)

점진적으로 이전 Pod를 새 Pod로 교체합니다.

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1  # 동시에 중단될 수 있는 최대 Pod 수
      maxSurge: 1        # 동시에 생성될 수 있는 추가 Pod 수
```

### Recreate

모든 기존 Pod를 종료한 후 새 Pod를 생성합니다.

```yaml title="workload-dep-recreate.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-1-dep
spec:
  replicas: 6
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: workload-1
  template:
    metadata:
      labels:
        app: workload-1
        color: blue
    spec:
      containers:
        - name: workload
          image: nginx:1.27
          ports:
            - containerPort: 80
      nodeSelector:
        kubernetes.io/os: linux
```

```bash
kubectl apply -f workload-dep-recreate.yaml
```

## 롤백

### 롤아웃 히스토리 확인

```bash
kubectl rollout history deployment/workload-1-dep
```

### 이전 버전으로 롤백

```bash
# 바로 이전 버전으로 롤백
kubectl rollout undo deployment/workload-1-dep

# 특정 리비전으로 롤백
kubectl rollout undo deployment/workload-1-dep --to-revision=2
```

### 특정 리비전 상세 정보

```bash
kubectl rollout history deployment/workload-1-dep --revision=3
```

## MinReadySeconds 설정

Pod가 준비 상태가 된 후 추가 대기 시간을 설정합니다:

```yaml
spec:
  minReadySeconds: 30
  replicas: 6
  template:
    metadata:
      labels:
        app: workload-1
        color: maroon
    spec:
      containers:
        - name: workload
          image: nginx:1.27
          ports:
            - containerPort: 80
```

이를 통해 Pod가 실제로 안정적인지 확인하는 시간을 확보할 수 있습니다.

## Revision History 제한

```yaml
spec:
  revisionHistoryLimit: 3  # 최근 3개의 ReplicaSet만 유지
  replicas: 6
  template:
    metadata:
      labels:
        app: workload-1
        color: orange
    spec:
      containers:
        - name: workload
          image: nginx:latest
          ports:
            - containerPort: 80
```

## 잘못된 이미지로 배포 (장애 시나리오)

```yaml title="workload-dep-invalid.yaml"
spec:
  replicas: 6
  template:
    metadata:
      labels:
        app: workload-1
        color: aqua
    spec:
      containers:
        - name: workload
          image: nginx:invalid-tag  # 존재하지 않는 이미지
          ports:
            - containerPort: 80
```

```bash
kubectl apply -f workload-dep-invalid.yaml --record

# Pod 상태 확인
kubectl get pods

# ImagePullBackOff 오류 확인
kubectl describe pod <pod-name>
```

이 경우 새 ReplicaSet이 생성되지만 Pod는 ImagePullBackOff 상태가 됩니다. 이전 ReplicaSet은 그대로 유지되어 서비스가 중단되지 않습니다.

```bash
# 이전 버전으로 롤백
kubectl rollout undo deployment/workload-1-dep
```

## 리소스 정리

```bash
kubectl delete deployment workload-1-dep
```

## 실습 과제

:::tip 실습 과제
1. nginx 이미지의 다양한 버전(1.18, 1.19, 1.20)으로 배포를 업데이트하고 롤아웃 히스토리를 확인하세요
2. Recreate 전략과 RollingUpdate 전략의 차이를 관찰하세요
3. 잘못된 이미지를 배포하고 롤백하는 과정을 연습하세요
4. `minReadySeconds`를 다양한 값으로 설정하고 롤아웃 속도를 관찰하세요
:::

## 다음 단계

[Service](./services)에서 Deployment를 외부에 노출하는 방법을 배웁니다.
