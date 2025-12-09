# Horizontal Pod Autoscaler

HPA(Horizontal Pod Autoscaler)를 사용하여 CPU와 Memory 메트릭 기반으로 Pod를 자동 확장하는 방법을 학습합니다.

## HPA란?

HPA는 워크로드의 메트릭을 모니터링하여 자동으로 Pod 개수를 조정하는 Kubernetes 리소스입니다.

### HPA 동작 방식

1. **메트릭 수집**: Metrics Server에서 현재 메트릭 확인
2. **계산**: 목표 메트릭과 비교하여 필요한 replica 수 계산
3. **스케일링**: Deployment/ReplicaSet의 replica 조정
4. **안정화**: Stabilization Window 동안 대기

### 지원 메트릭

* **Resource Metrics**: CPU, Memory (Metrics Server 필요)
* **Custom Metrics**: Prometheus 등 (Custom Metrics API 필요)
* **External Metrics**: Cloud provider 메트릭 (External Metrics API 필요)

## 사전 준비: Metrics Server

AKS는 기본적으로 Metrics Server가 설치되어 있습니다:

```bash
# Metrics Server 확인
kubectl get deployment metrics-server -n kube-system

# Pod 메트릭 확인
kubectl top pods

# Node 메트릭 확인
kubectl top nodes
```

## 실습 1: CPU 기반 HPA

### 1. 워크로드 배포

CPU 집약적인 PHP 애플리케이션을 배포합니다:

```yaml title="complex-web-dep.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: complex-web-dep
spec:
  selector:
    matchLabels:
      run: complex-web-pod
  replicas: 3  
  template:
    metadata:
      labels:
        run: complex-web-pod
        color: orange
    spec:
      containers:
      - name: complex-web
        image: registry.k8s.io/hpa-example
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 400m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: complex-web-svc
spec:
  selector:
    run: complex-web-pod
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
```

```bash
kubectl apply -f complex-web-dep.yaml

# Pod 확인
kubectl get pods -l run=complex-web-pod

# 메트릭 확인 (1-2분 대기)
kubectl top pods -l run=complex-web-pod
```

### 2. HPA 생성

```yaml title="complex-web-hpa.yaml"
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: complex-web-hpa-1
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: complex-web-dep
  minReplicas: 1
  maxReplicas: 12
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: AverageValue
        averageValue: 100m     # 평균 100m 유지
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 30    # 30초 동안 안정화
      policies:
      - type: Percent
        value: 50                        # 50%까지 축소 가능
        periodSeconds: 30
```

```bash
kubectl apply -f complex-web-hpa.yaml

# HPA 확인
kubectl get hpa

# 상세 정보
kubectl describe hpa complex-web-hpa-1
```

### 3. 부하 생성

```yaml title="complex-web-load.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: complex-web-load
spec:
  replicas: 1
  selector:
    matchLabels:
      app: load-generator
  template:
    metadata:
      labels:
        app: load-generator
    spec:
      containers:
      - name: load
        image: busybox
        command:
        - /bin/sh
        - -c
        - |
          while true; do
            wget -q -O- http://complex-web-svc;
          done
```

```bash
kubectl apply -f complex-web-load.yaml

# 메트릭 증가 확인
kubectl top pods -l run=complex-web-pod

# HPA 상태 확인
kubectl get hpa -w
```

### 4. 부하 증가

```bash
# 부하 생성기 증가
kubectl scale --replicas=15 deployment/complex-web-load

# HPA가 Pod를 증가시킴
kubectl get hpa -w

# Pod 개수 확인
kubectl get pods -l run=complex-web-pod
```

HPA가 자동으로 Pod를 증가시킵니다 (최대 12개).

### 5. 부하 감소

```bash
# 부하 생성기 감소
kubectl scale --replicas=1 deployment/complex-web-load

# HPA가 Pod를 감소시킴 (30초 stabilization 후)
kubectl get hpa -w

# Pod 개수 확인
kubectl get pods -l run=complex-web-pod
```

### 6. 부하 제거

```bash
# 부하 생성기 삭제
kubectl delete deployment complex-web-load

# HPA가 Pod를 최소값(1)으로 감소
kubectl get hpa -w
```

**주의**: 원래 replica(3)가 아닌 minReplicas(1)로 줄어듭니다.

## 실습 2: 다중 메트릭 HPA

CPU와 Memory를 동시에 모니터링:

```yaml title="complex-web-hpa2.yaml"
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: complex-web-hpa-1
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: complex-web-dep
  minReplicas: 2
  maxReplicas: 12
  metrics:
  # CPU 메트릭
  - type: Resource
    resource:
      name: cpu
      target:
        type: AverageValue
        averageValue: 100m
  # Memory 메트릭
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 70    # Request의 70%
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100                 # 100% 증가 가능
        periodSeconds: 15
      - type: Pods
        value: 4                   # 또는 4개씩 증가
        periodSeconds: 15
      selectPolicy: Max            # 더 공격적인 정책 선택
    scaleDown:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 50
        periodSeconds: 30
```

```bash
kubectl apply -f complex-web-hpa2.yaml

# HPA 확인
kubectl describe hpa complex-web-hpa-1
```

## 실습 3: Utilization vs AverageValue

### Utilization (백분율)

Request의 백분율로 계산:

```yaml
metrics:
- type: Resource
  resource:
    name: cpu
    target:
      type: Utilization
      averageUtilization: 50    # Request의 50%
```

예: Request가 300m이면 150m에서 스케일링

### AverageValue (절대값)

절대값으로 계산:

```yaml
metrics:
- type: Resource
  resource:
    name: cpu
    target:
      type: AverageValue
      averageValue: 100m        # 100m
```

Request와 무관하게 100m에서 스케일링

## HPA 계산 공식

```
desiredReplicas = ceil[currentReplicas * (currentMetric / targetMetric)]
```

예시:
- 현재 3개 replica
- 현재 평균 CPU: 200m
- 목표 CPU: 100m
- 계산: 3 * (200/100) = 6개

## AKS와 HPA

### Cluster Autoscaler와 함께 사용

```bash
# HPA가 Pod를 증가 → 노드 리소스 부족 → Cluster Autoscaler가 노드 추가

# 노드 확인
kubectl get nodes -w
```

### Azure Monitor 통합

```bash
# Container Insights에서 HPA 메트릭 확인
az aks show \
  --resource-group myResourceGroup \
  --name myAKSCluster \
  --query addonProfiles.omsagent.enabled
```

## 정리

```bash
kubectl delete deployment complex-web-dep complex-web-load
kubectl delete service complex-web-svc
kubectl delete hpa complex-web-hpa-1
```

## 핵심 정리

* **HPA**: 메트릭 기반 자동 Pod 확장
* **Metrics Server**: CPU/Memory 메트릭 수집
* **AverageValue**: 절대값 기준 스케일링
* **Utilization**: Request 대비 백분율 스케일링
* **Behavior**: 스케일링 속도 및 안정화 제어
* **다중 메트릭**: 여러 메트릭 동시 모니터링 (OR 조건)

## 베스트 프랙티스

1. **항상 Requests 설정**: HPA는 Requests 기준으로 동작
2. **적절한 minReplicas 설정**: 최소 가용성 보장
3. **Stabilization Window**: 불필요한 스케일링 방지
4. **Cluster Autoscaler 함께 사용**: Pod와 노드 모두 확장
5. **모니터링**: Azure Monitor로 HPA 동작 추적

## 실습 과제

1. Memory 기반 HPA를 생성하고 메모리 부하를 발생시켜 스케일링을 관찰해보세요.
2. Behavior 설정을 변경하여 스케일업/다운 속도를 조정해보세요.
3. minReplicas와 maxReplicas를 다르게 설정하며 동작을 확인해보세요.
4. Cluster Autoscaler와 함께 사용하여 노드가 자동 추가되는 것을 관찰해보세요.

## 다음 단계

[KEDA RabbitMQ 스케일링](./keda-rabbitmq)에서 이벤트 기반 스케일링을 학습합니다.
