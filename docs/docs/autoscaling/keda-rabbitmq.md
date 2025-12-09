# KEDA RabbitMQ 스케일링

KEDA(Kubernetes Event-Driven Autoscaling)를 사용하여 RabbitMQ 큐 길이 기반으로 Pod를 자동 확장하는 방법을 학습합니다.

## KEDA란?

KEDA는 이벤트 기반으로 Kubernetes 워크로드를 자동 확장하는 오픈소스 프로젝트입니다.

### KEDA 특징

* **Scale to Zero**: 이벤트가 없을 때 0으로 축소 (비용 절감)
* **다양한 Scaler**: RabbitMQ, Azure Service Bus, Kafka, Prometheus 등 50+ scalers
* **HPA 통합**: 내부적으로 HPA를 생성하여 관리
* **External Metrics**: 외부 시스템의 메트릭 활용

## 사전 준비: KEDA 설치

### Helm으로 KEDA 설치

```bash
# Helm repo 추가
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# KEDA 설치
helm install keda kedacore/keda --namespace keda --create-namespace

# KEDA 확인
kubectl get pods -n keda
```

또는 YAML로 설치:

```bash
kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.12.0/keda-2.12.0.yaml

# KEDA 확인
kubectl get deployment -n keda
```

## 실습 1: RabbitMQ 배포

### 1. ConfigMap 생성

```yaml title="rabbit-cm.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: rabbit-configmap
data:
  RABBITMQ_DEFAULT_USER: guest
  RABBITMQ_DEFAULT_PASS: guest
  RABBITMQ_HOST: rabbit-svc
  RABBITMQ_PORT: "5672"
  QUEUE_NAME: SampleQueue
```

```bash
kubectl apply -f rabbit-cm.yaml
```

### 2. RabbitMQ Deployment

```yaml title="rabbit-dep.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rabbit-dep
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rabbit-pod
  template:
    metadata:
      labels:
        app: rabbit-pod
    spec:
      containers:
      - name: rabbit-container
        image: rabbitmq:3-management
        ports:
        - name: rabbit-ui
          containerPort: 15672
        - name: rabbit-port
          containerPort: 5672
        envFrom:
        - configMapRef:
            name: rabbit-configmap
        resources:
          requests:
            cpu: 300m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
```

### 3. RabbitMQ Service

```yaml title="rabbit-svc.yaml"
apiVersion: v1
kind: Service
metadata:
  name: rabbit-svc
spec:
  selector:
    app: rabbit-pod
  ports:
  - name: rabbit-ui
    port: 15672
    targetPort: 15672
  - name: rabbit-port
    port: 5672
    targetPort: 5672
  type: ClusterIP
```

```bash
kubectl apply -f rabbit-dep.yaml -f rabbit-svc.yaml

# RabbitMQ 준비 대기
kubectl wait --for=condition=ready pod -l app=rabbit-pod --timeout=180s
```

### 4. RabbitMQ UI 접근

```bash
# Port forward
kubectl port-forward svc/rabbit-svc 15672:15672

# 브라우저에서 http://localhost:15672 접근
# ID: guest, PW: guest
```

## 실습 2: Queue Processor 배포

### 1. Queue Processor Deployment

```yaml title="queue-processor.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: queue-processor-dep
spec:
  replicas: 1
  selector:
    matchLabels:
      app: queue-processor
  template:
    metadata:
      labels:
        app: queue-processor
        color: OrangeRed
    spec:
      initContainers:
      - name: queue-checker
        image: scubakiz/queuechecker:latest
        envFrom:
        - configMapRef:
            name: rabbit-configmap
      containers:
      - name: queue-processor
        image: scubakiz/queueprocessor:latest
        envFrom:
        - configMapRef:
            name: rabbit-configmap
        env:
        - name: MIN_SLEEP_INTERVAL
          value: "10000"    # 메시지당 10-15초 처리 (느린 처리)
        - name: MAX_SLEEP_INTERVAL
          value: "15000"
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
```

```bash
kubectl apply -f queue-processor.yaml

# Pod 확인
kubectl get pods -l app=queue-processor
```

## 실습 3: 메시지 로딩

### 1. Queue Loader Job

```yaml title="queue-loader-job.yaml"
apiVersion: batch/v1
kind: Job
metadata:
  name: queue-loader-job
spec:
  ttlSecondsAfterFinished: 30
  template:    
    spec:
      restartPolicy: Never
      containers:
      - name: queue-loader
        image: scubakiz/queueloader:latest
        envFrom:
        - configMapRef:
            name: rabbit-configmap
        env:
        - name: ITEMS_TO_QUEUE
          value: "500"      # 500개 메시지 생성
```

```bash
kubectl apply -f queue-loader-job.yaml

# Job 확인
kubectl get jobs

# RabbitMQ UI에서 SampleQueue 확인
# 약 500개 메시지가 큐에 쌓임
```

### 2. 느린 처리 관찰

```bash
# 메시지 처리 속도 관찰
kubectl logs -f deployment/queue-processor-dep

# RabbitMQ UI에서 큐 길이 확인
# 메시지가 천천히 감소함
```

1개 Pod로는 처리 속도가 느립니다.

## 실습 4: KEDA ScaledObject 배포

### 1. KEDA ScaledObject 생성

```yaml title="keda-rabbit.yaml"
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: keda-rabbit-so  
spec: 
  scaleTargetRef:
    kind: Deployment
    name: queue-processor-dep  
  triggers:
  - type: rabbitmq
    metadata:
      protocol: amqp
      queueName: SampleQueue
      mode: QueueLength
      value: "10"                     # 메시지 10개당 Pod 1개
      host: amqp://guest:guest@rabbit-svc.default.svc.cluster.local:5672
  pollingInterval: 1                  # 1초마다 확인
  cooldownPeriod: 1                   # 축소 전 1초 대기
  minReplicaCount: 1                  # 최소 1개
  maxReplicaCount: 30                 # 최대 30개
  advanced:
    restoreToOriginalReplicaCount: false
    horizontalPodAutoscalerConfig:
      behavior:
        scaleUp:
          stabilizationWindowSeconds: 1
          policies:
          - type: Percent
            value: 100                # 100%까지 빠르게 증가
            periodSeconds: 1
          - type: Pods
            value: 10                 # 또는 10개씩 증가
            periodSeconds: 1
          selectPolicy: Max           # 더 공격적인 정책 선택
        scaleDown:
          stabilizationWindowSeconds: 20
          policies:
          - type: Percent
            value: 100
            periodSeconds: 1
```

```bash
kubectl apply -f keda-rabbit.yaml

# ScaledObject 확인
kubectl get scaledobject

# HPA 자동 생성 확인
kubectl get hpa
```

### 2. 자동 스케일링 관찰

```bash
# Pod 증가 관찰
kubectl get pods -l app=queue-processor -w

# HPA 상태 확인
kubectl get hpa -w

# 메시지 길이 확인
kubectl describe scaledobject keda-rabbit-so
```

큐에 500개 메시지가 있으므로 약 50개(500/10) Pod가 생성됩니다 (maxReplicaCount=30으로 제한).

### 3. 빠른 처리 확인

```bash
# RabbitMQ UI에서 메시지 빠르게 감소 확인
# 많은 Pod가 병렬로 처리

# 로그 확인
kubectl logs -l app=queue-processor --tail=10
```

### 4. Scale Down 관찰

```bash
# 메시지가 모두 처리되면 Pod 감소
kubectl get pods -l app=queue-processor -w

# HPA 확인
kubectl get hpa -w
```

20초 stabilization 후 Pod가 감소하여 minReplicaCount(1)로 돌아갑니다.

## 실습 5: Scale to Zero

minReplicaCount를 0으로 설정:

```yaml title="keda-rabbit-zero.yaml"
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: keda-rabbit-so  
spec: 
  scaleTargetRef:
    kind: Deployment
    name: queue-processor-dep  
  triggers:
  - type: rabbitmq
    metadata:
      protocol: amqp
      queueName: SampleQueue
      mode: QueueLength
      value: "10"
      host: amqp://guest:guest@rabbit-svc.default.svc.cluster.local:5672
  pollingInterval: 5
  cooldownPeriod: 30
  minReplicaCount: 0      # Scale to Zero
  maxReplicaCount: 30
```

```bash
kubectl apply -f keda-rabbit-zero.yaml

# 메시지가 없으면 0으로 축소
kubectl get pods -l app=queue-processor -w

# 새 메시지 추가 시 자동으로 Pod 생성
kubectl apply -f queue-loader-job.yaml
```

## AKS에서 KEDA 활용

### Azure Service Bus Scaler

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: servicebus-scaler
spec:
  scaleTargetRef:
    name: my-deployment
  triggers:
  - type: azure-servicebus
    metadata:
      queueName: myqueue
      namespace: myservicebus
      messageCount: "5"
    authenticationRef:
      name: servicebus-auth
```

### Azure Monitor Scaler

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: monitor-scaler
spec:
  scaleTargetRef:
    name: my-deployment
  triggers:
  - type: azure-monitor
    metadata:
      resourceURI: /subscriptions/.../resourceGroups/.../providers/...
      metricName: Percentage CPU
      targetValue: "70"
```

## 정리

```bash
kubectl delete scaledobject keda-rabbit-so
kubectl delete deployment queue-processor-dep rabbit-dep
kubectl delete service rabbit-svc
kubectl delete configmap rabbit-configmap
kubectl delete job queue-loader-job

# KEDA 제거 (선택)
helm uninstall keda -n keda
```

## 핵심 정리

* **KEDA**: 이벤트 기반 자동 확장
* **ScaledObject**: 스케일링 규칙 정의
* **Scale to Zero**: 비용 최적화
* **RabbitMQ Scaler**: 큐 길이 기반 스케일링
* **HPA 통합**: 내부적으로 HPA 생성
* **50+ Scalers**: 다양한 이벤트 소스 지원

## 베스트 프랙티스

1. **적절한 value 설정**: 메시지당 처리 시간 고려
2. **minReplicaCount**: 최소 가용성 보장 (0 또는 1)
3. **Stabilization Window**: 불필요한 스케일링 방지
4. **리소스 설정**: 각 Pod의 Requests/Limits 명시
5. **모니터링**: ScaledObject 메트릭 추적

## 실습 과제

1. value를 다르게 설정(5, 20, 50)하며 스케일링 동작을 관찰해보세요.
2. Azure Service Bus를 사용하는 ScaledObject를 생성해보세요.
3. 여러 개의 Trigger를 가진 ScaledObject를 만들어보세요.
4. Prometheus Scaler를 사용하여 커스텀 메트릭 기반 스케일링을 구현해보세요.

## 다음 단계

[KEDA Cron 스케일러](./keda-cron)에서 시간 기반 스케일링을 학습합니다.
