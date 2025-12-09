# KEDA Cron 스케일러

KEDA Cron Scaler를 사용하여 시간 기반으로 Pod를 자동 확장하는 방법을 학습합니다.

## Cron Scaler란?

Cron Scaler는 특정 시간대에 워크로드를 미리 확장하여 예상되는 트래픽 증가에 대비하는 스케일러입니다.

### 사용 사례

* **예측 가능한 트래픽**: 특정 시간대에 트래픽 증가 (예: 점심시간, 이벤트)
* **배치 작업**: 매일 특정 시간에 실행되는 작업
* **비용 최적화**: 사용하지 않는 시간대에 Scale to Zero
* **준비 시간**: 워크로드가 준비되는 데 시간이 필요한 경우

## 사전 준비

KEDA가 설치되어 있어야 합니다:

```bash
# KEDA 설치 확인
kubectl get pods -n keda

# 없으면 설치
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda --namespace keda --create-namespace
```

## 실습 1: 기본 Cron Scaler

### 1. 워크로드 Deployment

```yaml title="workload-dep.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-dep
spec:
  replicas: 1
  selector:
    matchLabels:
      app: workload
  template:
    metadata:
      labels:
        app: workload
        color: lime
    spec:
      containers:
      - name: nginx
        image: nginx:1.18
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
kubectl apply -f workload-dep.yaml

# Pod 확인
kubectl get pods -l app=workload
```

### 2. Cron ScaledObject 생성

매 2분마다 증가, 매 4분마다 감소:

```yaml title="keda-cron.yaml"
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: cron-scaledobject  
spec:
  scaleTargetRef:
    kind: Deployment
    name: workload-dep
  pollingInterval: 10             # 10초마다 확인
  cooldownPeriod: 1               # 축소 전 1초 대기
  minReplicaCount: 0              # 최소 0개
  maxReplicaCount: 12             # 최대 12개
  triggers:
  - type: cron
    metadata:
      timezone: Etc/UTC           # UTC 타임존
      start: 1/2 * * * *           # 매 2분마다 (1, 3, 5, 7, ... 분)
      end: 1/4 * * * *             # 매 4분마다 (1, 5, 9, 13, ... 분)
      desiredReplicas: "12"       # 목표 replica 수
  advanced:
    restoreToOriginalReplicaCount: false
    horizontalPodAutoscalerConfig:
      behavior:
        scaleUp:
          stabilizationWindowSeconds: 1
          policies:
          - type: Percent
            value: 100
            periodSeconds: 1
          - type: Pods
            value: 12
            periodSeconds: 1
          selectPolicy: Max
```

```bash
kubectl apply -f keda-cron.yaml

# ScaledObject 확인
kubectl get scaledobject

# HPA 확인
kubectl get hpa
```

### 3. 스케일링 관찰

```bash
# Pod 변화 관찰
kubectl get pods -l app=workload -w

# 시간별 동작:
# - 1, 3, 5, 7분: 12개로 증가
# - 1, 5, 9, 13분: 0개로 감소
```

## Cron 표현식 이해

### 표준 Cron 형식

```
┌───────────── 분 (0 - 59)
│ ┌───────────── 시 (0 - 23)
│ │ ┌───────────── 일 (1 - 31)
│ │ │ ┌───────────── 월 (1 - 12)
│ │ │ │ ┌───────────── 요일 (0 - 6) (일요일=0)
│ │ │ │ │
* * * * *
```

### 예시

| 표현식 | 의미 |
|--------|------|
| `0 9 * * *` | 매일 오전 9시 |
| `30 17 * * 1-5` | 평일 오후 5시 30분 |
| `0 */2 * * *` | 매 2시간마다 |
| `0 0 1 * *` | 매월 1일 자정 |
| `1/2 * * * *` | 매 2분마다 (1, 3, 5분) |

## 실습 2: 업무 시간 기반 스케일링

### 평일 업무 시간에만 확장

```yaml title="business-hours-scaler.yaml"
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: business-hours-scaler
spec:
  scaleTargetRef:
    kind: Deployment
    name: workload-dep
  minReplicaCount: 0
  maxReplicaCount: 10
  triggers:
  - type: cron
    metadata:
      timezone: Asia/Seoul         # 한국 시간
      start: 0 9 * * 1-5           # 평일 오전 9시
      end: 0 18 * * 1-5            # 평일 오후 6시
      desiredReplicas: "10"
```

```bash
kubectl apply -f business-hours-scaler.yaml
```

## 실습 3: 다중 Cron Trigger

여러 시간대에 다른 replica 수:

```yaml title="multi-cron-scaler.yaml"
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: multi-cron-scaler
spec:
  scaleTargetRef:
    kind: Deployment
    name: workload-dep
  minReplicaCount: 0
  maxReplicaCount: 20
  triggers:
  # 아침 피크 타임: 5개
  - type: cron
    metadata:
      timezone: Asia/Seoul
      start: 0 8 * * 1-5
      end: 0 10 * * 1-5
      desiredReplicas: "5"
  # 점심 피크 타임: 10개
  - type: cron
    metadata:
      timezone: Asia/Seoul
      start: 0 12 * * 1-5
      end: 0 14 * * 1-5
      desiredReplicas: "10"
  # 저녁 피크 타임: 8개
  - type: cron
    metadata:
      timezone: Asia/Seoul
      start: 0 18 * * 1-5
      end: 0 20 * * 1-5
      desiredReplicas: "8"
```

```bash
kubectl apply -f multi-cron-scaler.yaml
```

**주의**: 여러 Trigger가 동시에 활성화되면 가장 높은 desiredReplicas가 적용됩니다.

## 실습 4: Cron + 다른 Scaler 결합

Cron과 CPU 메트릭을 함께 사용:

```yaml title="cron-cpu-scaler.yaml"
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: cron-cpu-scaler
spec:
  scaleTargetRef:
    kind: Deployment
    name: workload-dep
  minReplicaCount: 1
  maxReplicaCount: 20
  triggers:
  # Cron: 업무 시간에 최소 5개 유지
  - type: cron
    metadata:
      timezone: Asia/Seoul
      start: 0 9 * * 1-5
      end: 0 18 * * 1-5
      desiredReplicas: "5"
  # CPU: 추가 트래픽에 대응
  - type: cpu
    metricType: Utilization
    metadata:
      value: "70"
```

```bash
kubectl apply -f cron-cpu-scaler.yaml
```

업무 시간에는 최소 5개가 유지되고, CPU 사용률이 높으면 추가로 증가합니다.

## 실습 5: 주말 Scale to Zero

주말에는 완전히 중지:

```yaml title="weekday-only-scaler.yaml"
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: weekday-only-scaler
spec:
  scaleTargetRef:
    kind: Deployment
    name: workload-dep
  minReplicaCount: 0
  maxReplicaCount: 10
  triggers:
  - type: cron
    metadata:
      timezone: Asia/Seoul
      start: 0 0 * * 1            # 월요일 자정
      end: 0 0 * * 6              # 토요일 자정
      desiredReplicas: "3"
```

```bash
kubectl apply -f weekday-only-scaler.yaml

# 월-금: 3개 유지
# 토-일: 0개로 축소 (비용 절감)
```

## AKS에서 Cron Scaler 활용

### 배치 작업 스케줄링

```yaml title="batch-job-scaler.yaml"
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: batch-job-scaler
spec:
  scaleTargetRef:
    kind: Deployment
    name: batch-processor
  minReplicaCount: 0
  maxReplicaCount: 50
  triggers:
  - type: cron
    metadata:
      timezone: Asia/Seoul
      start: 0 2 * * *             # 매일 새벽 2시
      end: 0 4 * * *               # 매일 새벽 4시
      desiredReplicas: "50"        # 배치 처리용 대량 Pod
```

### 이벤트 준비

```yaml title="event-prep-scaler.yaml"
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: event-prep-scaler
spec:
  scaleTargetRef:
    kind: Deployment
    name: event-handler
  minReplicaCount: 0
  maxReplicaCount: 100
  triggers:
  - type: cron
    metadata:
      timezone: Asia/Seoul
      start: 50 19 25 12 *         # 12월 25일 오후 7시 50분
      end: 0 23 25 12 *            # 12월 25일 오후 11시
      desiredReplicas: "100"       # 크리스마스 이벤트 대비
```

## 정리

```bash
kubectl delete scaledobject cron-scaledobject business-hours-scaler \
  multi-cron-scaler cron-cpu-scaler weekday-only-scaler \
  batch-job-scaler event-prep-scaler
kubectl delete deployment workload-dep
```

## 핵심 정리

* **Cron Scaler**: 시간 기반 스케일링
* **start/end**: 증가/감소 시간 지정
* **desiredReplicas**: 목표 replica 수
* **Timezone**: 타임존 지정 (UTC, Asia/Seoul 등)
* **다중 Trigger**: 여러 시간대 설정 가능
* **Scale to Zero**: 사용하지 않는 시간 비용 절감

## 베스트 프랙티스

1. **적절한 Timezone 설정**: 서비스 지역에 맞게 설정
2. **준비 시간 고려**: 이벤트 전에 미리 확장
3. **다른 Scaler와 결합**: Cron + CPU/Memory
4. **모니터링**: 실제 트래픽 패턴 분석 후 조정
5. **테스트**: 짧은 간격으로 먼저 테스트

## 실습 과제

1. 매시간 정각에 10개로 증가하고 30분에 1개로 감소하는 ScaledObject를 만들어보세요.
2. 주중과 주말에 다른 replica 수를 유지하는 설정을 구성해보세요.
3. Cron과 RabbitMQ Scaler를 함께 사용하여 하이브리드 스케일링을 구현해보세요.
4. 실제 서비스의 트래픽 패턴을 분석하여 최적의 Cron 스케줄을 설계해보세요.

## 마무리

축하합니다! 모든 오토스케일링 실습을 완료했습니다. 이제 다음 주제를 학습할 수 있습니다:

* [고급 Kubernetes 기능](../advanced-kubernetes/intro)
* [모니터링](../monitoring/overview)
* [Istio 서비스 메시](../hands-on-labs/request-routing)
