# 헬스 체크 (Health Checks)

Kubernetes는 컨테이너의 상태를 주기적으로 확인하여 애플리케이션의 안정성을 보장합니다. Probe를 통해 컨테이너의 생존 여부, 트래픽 수신 준비 상태, 초기 시작 완료 여부를 모니터링할 수 있습니다.

## Probe의 종류

### 1. Liveness Probe - 생존 확인

**목적**: 컨테이너가 정상적으로 실행 중인지 확인

**동작**:
- 컨테이너가 응답하지 않거나 교착 상태(deadlock)인 경우 감지
- 실패 시 컨테이너를 재시작하여 복구

**사용 사례**:
- 애플리케이션이 무한 루프에 빠진 경우
- 메모리 누수로 인한 hang 상태
- 내부 로직 오류로 응답 불가 상태

### 2. Readiness Probe - 준비 상태 확인

**목적**: 컨테이너가 트래픽을 받을 준비가 되었는지 확인

**동작**:
- 프로브 실패 시 Service의 Endpoints에서 Pod 제거 (트래픽 차단)
- 컨테이너는 재시작하지 않음
- 프로브 성공 시 다시 Endpoints에 추가

**사용 사례**:
- 애플리케이션 초기화 중 (DB 연결, 캐시 로딩)
- 일시적인 외부 의존성 문제
- 설정 파일 로딩 중

### 3. Startup Probe - 시작 확인

**목적**: 컨테이너 애플리케이션이 시작되었는지 확인

**동작**:
- 시작이 완료되면 Liveness/Readiness Probe가 동작 시작
- 느리게 시작하는 애플리케이션을 위한 특별 처리
- 실패 시 컨테이너 재시작

**사용 사례**:
- 레거시 애플리케이션 (시작에 오랜 시간 소요)
- 대용량 데이터 로딩이 필요한 경우
- JVM 애플리케이션 등 초기화가 느린 경우

## Probe의 실행 순서

```
컨테이너 시작
   ↓
Startup Probe 시작 (설정된 경우)
   ↓
Startup Probe 성공
   ↓
Liveness Probe + Readiness Probe 시작
   ↓
애플리케이션 실행 중
```

## Probe 메커니즘

### 1. HTTP GET

HTTP 요청을 보내서 응답 코드 확인
- **성공**: 200 ≤ 응답 코드 < 400
- **실패**: 그 외 응답 코드 또는 타임아웃

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
    httpHeaders:
    - name: Custom-Header
      value: Awesome
  initialDelaySeconds: 3
  periodSeconds: 3
```

### 2. TCP Socket

지정된 포트에 TCP 연결 시도
- **성공**: 연결 성공
- **실패**: 연결 실패

```yaml
readinessProbe:
  tcpSocket:
    port: 3306
  initialDelaySeconds: 5
  periodSeconds: 10
```

### 3. Exec

컨테이너 내부에서 명령어 실행
- **성공**: 종료 코드 0
- **실패**: 0이 아닌 종료 코드

```yaml
livenessProbe:
  exec:
    command:
    - cat
    - /tmp/healthy
  initialDelaySeconds: 5
  periodSeconds: 5
```

## Probe 설정 매개변수

| 매개변수 | 설명 | 기본값 |
|---------|------|--------|
| `initialDelaySeconds` | 컨테이너 시작 후 프로브 시작까지 대기 시간 | 0초 |
| `periodSeconds` | 프로브 실행 간격 | 10초 |
| `timeoutSeconds` | 프로브 타임아웃 | 1초 |
| `successThreshold` | 성공으로 간주하기 위한 연속 성공 횟수 | 1회 |
| `failureThreshold` | 실패로 간주하기 위한 연속 실패 횟수 | 3회 |

## 실습 1: Startup Probe

느리게 시작하는 애플리케이션을 위한 Startup Probe를 구성합니다.

### Service 생성

**probes-svc.yaml**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: probes-svc
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: probes
```

### Startup Probe Deployment

**dep-startup-probe.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dep-startup-probe
  labels:
    app: demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: probes
  template:
    metadata:
      labels:
        app: probes
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
        # Startup Probe: 컨테이너가 시작되었는지 확인
        # 15초마다 체크, 1번만 실패해도 재시작
        # 최대 15초 대기 (periodSeconds × failureThreshold)
        startupProbe:
          httpGet:
            path: /healthy  # 존재하지 않는 경로
            port: 80
          failureThreshold: 1
          periodSeconds: 15
```

**배포 및 관찰**:
```bash
# Service 생성
kubectl apply -f probes-svc.yaml

# Deployment 생성
kubectl apply -f dep-startup-probe.yaml

# Pod 상태 확인
kubectl get pods -l app=probes -w
```

**관찰 결과**:
- Pod가 `Running` 상태이지만 `READY`는 `0/1`
- Startup Probe가 `/healthy` 경로를 찾지 못해 실패
- 15초 후 컨테이너 재시작
- `RESTARTS` 숫자 계속 증가

**Pod 상세 정보**:
```bash
POD_NAME=$(kubectl get pod -l app=probes -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod $POD_NAME
```

**이벤트 확인**:
```
Events:
  Type     Reason     Message
  ----     ------     -------
  Warning  Unhealthy  Startup probe failed: HTTP probe failed with statuscode: 404
  Normal   Killing    Container nginx failed startup probe, will be restarted
```

**Service 상태 확인**:
```bash
kubectl describe svc probes-svc
```

Endpoints가 비어있습니다 - Pod가 준비되지 않았기 때문입니다.

## 실습 2: Liveness Probe

컨테이너가 정상 작동하는지 주기적으로 확인합니다.

### Liveness Probe Deployment

**dep-liveness-probe.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dep-liveness-probe
  labels:
    app: demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: probes
  template:
    metadata:
      labels:
        app: probes
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
        # Liveness Probe: 컨테이너가 살아있는지 확인
        # 30초 후 시작, 5초마다 체크
        # 2번 연속 실패하면 컨테이너 재시작
        livenessProbe:
          httpGet:
            path: /healthy  # 존재하지 않는 경로
            port: 80
          failureThreshold: 2
          periodSeconds: 5
          initialDelaySeconds: 30
```

**배포 및 관찰**:
```bash
# 기존 Deployment 삭제
kubectl delete deploy dep-startup-probe

# 새 Deployment 생성
kubectl apply -f dep-liveness-probe.yaml

# Pod 상태 확인
kubectl get pods -l app=probes -w
```

**관찰 결과**:
1. **초기 30초**: Pod가 `Running`이고 `READY 1/1` 상태
2. **30초 후**: Liveness Probe 시작
3. **40초 후**: 2번 연속 실패 (5초 × 2)
4. **컨테이너 재시작**: `RESTARTS` 숫자 증가
5. **Service는 계속 사용 가능**: 재시작 중에도 트래픽 처리

**Service 확인**:
```bash
# Service의 외부 IP 확인
kubectl get svc probes-svc

# Service는 사용 가능 (Endpoints에 Pod 존재)
kubectl describe svc probes-svc

# 접속 테스트 (재시작 중에도 일부 요청은 성공)
SERVICE_IP=$(kubectl get svc probes-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
while true; do curl -s -o /dev/null -w "%{http_code}\n" http://$SERVICE_IP/; sleep 1; done
```

**Liveness의 특징**:
- 컨테이너를 재시작하지만 Pod는 유지
- 재시작 중 짧은 다운타임 발생 가능
- Service Endpoints에서 제거되지 않음

## 실습 3: Readiness Probe

컨테이너가 트래픽을 받을 준비가 되었는지 확인합니다.

### Readiness Probe Deployment

**dep-readiness-probe.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dep-readiness-probe
  labels:
    app: demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: probes
  template:
    metadata:
      labels:
        app: probes
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
        # Readiness Probe: 트래픽을 받을 준비가 되었는지 확인
        # 60초 후 시작, 5초마다 체크
        # 2번 연속 실패하면 Service Endpoints에서 제거
        readinessProbe:
          tcpSocket:
            port: 80
          failureThreshold: 2
          periodSeconds: 5
          initialDelaySeconds: 60
```

**배포 및 관찰**:
```bash
# 기존 Deployment 삭제
kubectl delete deploy dep-liveness-probe

# 새 Deployment 생성
kubectl apply -f dep-readiness-probe.yaml

# Pod 상태 확인
kubectl get pods -l app=probes -w
```

**관찰 결과**:
1. **초기 60초**: Pod는 `Running`이지만 `READY 0/1`
2. **Service 사용 불가**: Endpoints에 Pod가 없음
3. **60초 후**: Readiness Probe 성공, `READY 1/1`
4. **Service 사용 가능**: Endpoints에 Pod 추가됨

**Service 상태 변화 관찰**:
```bash
# 초기 60초 동안 - Endpoints 없음
kubectl get endpoints probes-svc

# 60초 후 - Pod 추가됨
kubectl get endpoints probes-svc -w
```

**접속 테스트**:
```bash
# 초기 60초 동안은 연결 실패
curl http://$SERVICE_IP/

# 60초 후 정상 접속
curl http://$SERVICE_IP/
```

**Readiness의 특징**:
- 컨테이너를 재시작하지 않음
- Service Endpoints에서만 제거/추가
- 애플리케이션 준비 상태를 표시

## 실습 4: 모든 Probe 조합

실제 프로덕션 환경에서 권장되는 설정입니다.

**dep-all-probes.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dep-all-probes
  labels:
    app: demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: probes-all
  template:
    metadata:
      labels:
        app: probes-all
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
        # Startup Probe: 초기 시작 확인 (최대 300초 대기)
        startupProbe:
          httpGet:
            path: /
            port: 80
          failureThreshold: 30
          periodSeconds: 10
        # Liveness Probe: 생존 확인
        livenessProbe:
          httpGet:
            path: /
            port: 80
          periodSeconds: 10
          failureThreshold: 3
        # Readiness Probe: 트래픽 수신 준비 확인
        readinessProbe:
          httpGet:
            path: /
            port: 80
          periodSeconds: 5
          failureThreshold: 2
```

**배포 및 관찰**:
```bash
# Service 생성 (selector를 probes-all로 변경)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: probes-all-svc
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: probes-all
EOF

# Deployment 생성
kubectl apply -f dep-all-probes.yaml

# Pod 상태 확인
kubectl get pods -l app=probes-all -w
```

**관찰 결과**:
1. **Startup Probe 실행**: 컨테이너 시작 후 바로 시작
2. **Startup 성공**: `/` 경로가 존재하므로 성공
3. **Liveness/Readiness 시작**: Startup 성공 후 시작
4. **모두 성공**: Pod가 `READY 1/1` 상태로 전환

## Probe 실패 시나리오 테스트

### 헬스 체크 엔드포인트를 가진 애플리케이션

**app-with-health.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-health
spec:
  replicas: 2
  selector:
    matchLabels:
      app: health-app
  template:
    metadata:
      labels:
        app: health-app
    spec:
      containers:
      - name: app
        image: hashicorp/http-echo
        args:
        - "-text=healthy"
        - "-listen=:8080"
        ports:
        - containerPort: 8080
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 3
---
apiVersion: v1
kind: Service
metadata:
  name: health-app-svc
spec:
  type: LoadBalancer
  selector:
    app: health-app
  ports:
  - port: 80
    targetPort: 8080
```

**배포 및 테스트**:
```bash
kubectl apply -f app-with-health.yaml

# Pod 확인
kubectl get pods -l app=health-app

# 한 Pod의 헬스 체크를 수동으로 실패시키기
POD_NAME=$(kubectl get pod -l app=health-app -o jsonpath='{.items[0].metadata.name}')

# Pod 내부에 접속하여 프로세스 종료 (liveness 실패 유도)
kubectl exec $POD_NAME -- pkill http-echo

# Pod 재시작 관찰
kubectl get pods -l app=health-app -w
```

## Probe 설정 가이드

### Startup Probe 설정

느리게 시작하는 애플리케이션:
```yaml
startupProbe:
  httpGet:
    path: /healthz
    port: 8080
  failureThreshold: 30  # 최대 시도 횟수
  periodSeconds: 10     # 10초마다 체크 = 최대 300초 대기
```

### Liveness Probe 설정

애플리케이션 교착 상태 감지:
```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 30  # 충분한 시작 시간
  periodSeconds: 10        # 자주 체크하지 않음
  timeoutSeconds: 5        # 응답 대기 시간
  failureThreshold: 3      # 3번 실패 시 재시작
```

### Readiness Probe 설정

트래픽 수신 준비 확인:
```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 10  # 짧은 대기 시간
  periodSeconds: 5         # 자주 체크
  timeoutSeconds: 3
  failureThreshold: 2      # 빠른 격리
  successThreshold: 1      # 빠른 복구
```

## 헬스 체크 엔드포인트 구현 예시

### Go 예시

```go
http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
    // Liveness: 프로세스가 살아있는지만 확인
    w.WriteHeader(http.StatusOK)
})

http.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
    // Readiness: DB 연결, 의존성 등 확인
    if !checkDatabaseConnection() {
        w.WriteHeader(http.StatusServiceUnavailable)
        return
    }
    w.WriteHeader(http.StatusOK)
})
```

### Python (Flask) 예시

```python
@app.route('/healthz')
def healthz():
    # Liveness
    return 'OK', 200

@app.route('/ready')
def ready():
    # Readiness
    if not check_database():
        return 'Not Ready', 503
    return 'Ready', 200
```

### Node.js (Express) 예시

```javascript
app.get('/healthz', (req, res) => {
    // Liveness
    res.status(200).send('OK');
});

app.get('/ready', async (req, res) => {
    // Readiness
    try {
        await checkDependencies();
        res.status(200).send('Ready');
    } catch (error) {
        res.status(503).send('Not Ready');
    }
});
```

## 정리

```bash
# Deployment 삭제
kubectl delete deploy -l app=demo

# Service 삭제
kubectl delete svc probes-svc probes-all-svc health-app-svc
```

## 베스트 프랙티스

1. **모든 프로덕션 워크로드에 Probe 설정**
   - 최소한 Liveness와 Readiness는 필수

2. **적절한 타이밍 설정**
   - `initialDelaySeconds`: 애플리케이션 시작 시간보다 길게
   - `periodSeconds`: 너무 짧으면 오버헤드, 너무 길면 감지 지연
   - `timeoutSeconds`: 네트워크 지연 고려

3. **Startup Probe 활용**
   - 레거시 애플리케이션
   - JVM 기반 애플리케이션
   - 초기화에 오랜 시간이 걸리는 경우

4. **헬스 체크 엔드포인트는 가볍게**
   - 간단한 상태 확인만 수행
   - 무거운 로직이나 외부 호출 최소화
   - 캐싱 활용

5. **Liveness와 Readiness 분리**
   - Liveness: 프로세스 상태만 확인
   - Readiness: 의존성, 연결 상태 등 확인

6. **failureThreshold 신중히 설정**
   - 너무 낮으면 일시적 문제로 재시작
   - 너무 높으면 문제 감지 지연

## 실습 과제

1. **Startup Probe 실습**
   - 초기화에 30초가 걸리는 애플리케이션 시뮬레이션
   - Startup Probe 설정하여 정상 시작 확인

2. **Liveness Probe 테스트**
   - 애플리케이션 배포 후 프로세스 강제 종료
   - 자동 재시작 관찰

3. **Readiness Probe 테스트**
   - 의존성 문제 시뮬레이션
   - Service에서 자동 제거/추가 확인

4. **모든 Probe 조합**
   - 3가지 Probe 모두 설정
   - 각각의 동작 이해 및 검증

## 다음 단계

다음 섹션에서는 [Init Container](./init-containers)를 통한 컨테이너 초기화 패턴을 학습합니다.

## 참고 자료

- [Kubernetes Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Container probes](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#container-probes)
- [헬스 체크 패턴](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-a-liveness-http-request)
