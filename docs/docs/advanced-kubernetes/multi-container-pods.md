# Multi-Container Pods

하나의 Pod에 여러 컨테이너를 배치하여 긴밀하게 협력하는 패턴입니다. 각 컨테이너는 특정 역할을 수행하며, 네트워크와 스토리지를 공유합니다.

## Multi-Container의 필요성

### 단일 책임 원칙

각 컨테이너는 하나의 명확한 역할을 수행:
- **메인 애플리케이션**: 핵심 비즈니스 로직
- **사이드카**: 로깅, 모니터링, 프록시
- **어댑터**: 데이터 변환, 포맷 변경
- **앰버서더**: 외부 서비스 연결 관리

### Multi-Container의 장점

✅ **리소스 공유**
- 같은 네트워크 네임스페이스 (localhost로 통신)
- 볼륨 공유 (파일시스템 공유)
- IPC (Inter-Process Communication)

✅ **생명주기 동기화**
- 함께 시작하고 함께 종료
- 같은 노드에 스케줄링 보장
- 동일한 재시작 정책

✅ **모듈화 및 재사용**
- 독립적인 이미지 관리
- 컨테이너별 버전 관리
- 재사용 가능한 사이드카 패턴

## Multi-Container 패턴

### 1. Sidecar 패턴

메인 컨테이너를 보조하는 컨테이너를 추가합니다.

**사용 사례**:
- 로그 수집 및 전송
- 모니터링 메트릭 수집
- 설정 동기화
- 프록시 (Service Mesh의 Envoy)

**구조**:
```
┌──────────────────────────────┐
│         Pod                  │
│  ┌────────────┐              │
│  │   Main     │              │
│  │   App      │              │
│  └─────┬──────┘              │
│        │ shared volume       │
│  ┌─────┴──────┐              │
│  │  Sidecar   │              │
│  │  (Logger)  │              │
│  └────────────┘              │
└──────────────────────────────┘
```

### 2. Ambassador 패턴

외부 서비스와의 통신을 대리하는 프록시 컨테이너입니다.

**사용 사례**:
- 데이터베이스 연결 프록시
- 외부 API 호출 관리
- 캐싱 레이어
- 리트라이 및 서킷 브레이커

**구조**:
```
┌──────────────────────────────┐
│         Pod                  │
│  ┌────────────┐              │
│  │   Main     │              │
│  │   App      ├──localhost── │
│  └────────────┘              │
│  ┌────────────┐              │
│  │ Ambassador ├──external──> Database
│  │  (Proxy)   │              │
│  └────────────┘              │
└──────────────────────────────┘
```

### 3. Adapter 패턴

메인 컨테이너의 출력을 표준화하거나 변환합니다.

**사용 사례**:
- 로그 포맷 변환
- 메트릭 포맷 표준화
- 데이터 정규화
- 모니터링 시스템 연동

**구조**:
```
┌──────────────────────────────┐
│         Pod                  │
│  ┌────────────┐              │
│  │   Main     │              │
│  │   App      │ raw logs     │
│  └─────┬──────┘              │
│        │ shared volume       │
│  ┌─────┴──────┐              │
│  │  Adapter   │ JSON format  │
│  │ (Converter)├────────────> │
│  └────────────┘              │
└──────────────────────────────┘
```

## 실습 1: Sidecar 패턴 - 로그 수집

### Nginx + 로그 사이드카

**sidecar-logging.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-with-sidecar
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-sidecar
  template:
    metadata:
      labels:
        app: nginx-sidecar
    spec:
      # 공유 볼륨
      volumes:
      - name: logs
        emptyDir: {}
      
      containers:
      # 메인 컨테이너: Nginx
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
        volumeMounts:
        - name: logs
          mountPath: /var/log/nginx
      
      # 사이드카: 로그 수집기
      - name: log-shipper
        image: busybox
        command:
        - sh
        - -c
        - |
          # access.log를 실시간으로 읽어서 출력
          tail -f /var/log/nginx/access.log
        volumeMounts:
        - name: logs
          mountPath: /var/log/nginx
          readOnly: true
```

**배포 및 테스트**:
```bash
# Deployment 생성
kubectl apply -f sidecar-logging.yaml

# Service 생성
kubectl expose deployment nginx-with-sidecar --type=LoadBalancer --port=80

# Pod 확인
kubectl get pods -l app=nginx-sidecar

# 외부 IP로 접속하여 트래픽 생성
SERVICE_IP=$(kubectl get svc nginx-with-sidecar -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$SERVICE_IP/

# 사이드카 컨테이너의 로그 확인 (Nginx 접근 로그)
POD_NAME=$(kubectl get pod -l app=nginx-sidecar -o jsonpath='{.items[0].metadata.name}')
kubectl logs $POD_NAME -c log-shipper
```

**로그 출력 예시**:
```
192.168.1.1 - - [09/Dec/2025:10:30:45 +0000] "GET / HTTP/1.1" 200 612
```

## 실습 2: 문제가 있는 Multi-Container Pod

스크립트에서 참조한 예제를 재현합니다.

**multi-dep.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: multi-dep
spec:
  replicas: 1
  selector:
    matchLabels:
      app: multi-1
  template:
    metadata:
      labels:
        app: multi-1
        color: lime
    spec:
      containers:
      # 1. Nginx - 잘못된 포트 설정
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 8080  # Nginx는 기본적으로 80 포트 사용
          protocol: TCP
      
      # 2. MySQL - 환경 변수 누락 (주석 처리됨)
      - name: mysql
        image: mysql:5.7
        # env:
        # - name: MYSQL_ALLOW_EMPTY_PASSWORD
        #   value: "true"
        ports:
        - containerPort: 3306
          protocol: TCP
        resources:
          requests:
            cpu: 200m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
      
      # 3. Counter - 정상 동작
      - name: counter
        image: centos:7
        command:
        - "bin/bash"
        - "-c"
        - "for i in {1..99}; do echo $i; sleep 1s; done"
      
      # 4. Someother - 잘못된 명령어 (sleep에 음수 값)
      - name: someother
        image: centos:7
        command:
        - "bin/bash"
        - "-c"
        - "sleep 10s; for i in {1..99}; do echo $i; sleep -100; done"
```

**배포 및 관찰**:
```bash
# Deployment 생성
kubectl apply -f multi-dep.yaml

# Pod 상태 확인
kubectl get pods -l app=multi-1
```

**예상 결과**:
```
NAME                        READY   STATUS    RESTARTS   AGE
multi-dep-xxxx              2/4     Running   0          30s
```

**문제 분석**:
```bash
POD_NAME=$(kubectl get pod -l app=multi-1 -o jsonpath='{.items[0].metadata.name}')

# Pod 상세 정보
kubectl describe pod $POD_NAME

# 각 컨테이너 상태 확인
kubectl get pod $POD_NAME -o jsonpath='{.status.containerStatuses[*].name}' | tr ' ' '\n'
kubectl get pod $POD_NAME -o jsonpath='{.status.containerStatuses[*].state}' | jq .
```

**컨테이너별 문제**:

1. **nginx**: `Running` (포트는 틀렸지만 실행은 됨)
2. **mysql**: `CrashLoopBackOff` (환경 변수 필요)
3. **counter**: `Running` → `Completed` (정상 종료)
4. **someother**: `Error` (잘못된 sleep 인자)

**MySQL 로그 확인**:
```bash
kubectl logs $POD_NAME -c mysql
```

**에러 메시지**:
```
error: database is uninitialized and password option is not specified
  You need to specify one of MYSQL_ROOT_PASSWORD, MYSQL_ALLOW_EMPTY_PASSWORD and MYSQL_RANDOM_ROOT_PASSWORD
```

**someother 로그 확인**:
```bash
kubectl logs $POD_NAME -c someother
```

**에러 메시지**:
```
sleep: invalid time interval '-100'
```

## 실습 3: 수정된 Multi-Container Pod

문제를 수정한 버전입니다.

**multi-dep-fixed.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: multi-dep-fixed
spec:
  replicas: 1
  selector:
    matchLabels:
      app: multi-fixed
  template:
    metadata:
      labels:
        app: multi-fixed
    spec:
      containers:
      # 1. Nginx - 올바른 포트
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80  # ✅ 수정됨
          protocol: TCP
      
      # 2. MySQL - 환경 변수 추가
      - name: mysql
        image: mysql:5.7
        env:
        - name: MYSQL_ALLOW_EMPTY_PASSWORD  # ✅ 추가됨
          value: "true"
        ports:
        - containerPort: 3306
          protocol: TCP
        resources:
          requests:
            cpu: 200m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
      
      # 3. Counter - 계속 실행되도록 수정
      - name: counter
        image: centos:7
        command:
        - "bin/bash"
        - "-c"
        - "while true; do for i in {1..99}; do echo $i; sleep 1s; done; done"  # ✅ 무한 루프
      
      # 4. Someother - 올바른 sleep 값
      - name: monitor
        image: centos:7
        command:
        - "bin/bash"
        - "-c"
        - |
          sleep 10
          while true; do
            echo "Monitoring... $(date)"
            sleep 30  # ✅ 양수 값
          done
```

**배포 및 확인**:
```bash
# 수정된 버전 배포
kubectl apply -f multi-dep-fixed.yaml

# Pod 상태 확인
kubectl get pods -l app=multi-fixed
```

**예상 결과**:
```
NAME                              READY   STATUS    RESTARTS   AGE
multi-dep-fixed-xxxx              4/4     Running   0          30s
```

모든 컨테이너가 정상 실행됩니다!

## 실습 4: Sidecar 패턴 - Prometheus Exporter

메인 애플리케이션의 메트릭을 Prometheus 형식으로 노출하는 사이드카입니다.

**app-with-exporter.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-exporter
spec:
  replicas: 1
  selector:
    matchLabels:
      app: metrics-app
  template:
    metadata:
      labels:
        app: metrics-app
    spec:
      volumes:
      - name: metrics
        emptyDir: {}
      
      containers:
      # 메인 애플리케이션
      - name: app
        image: nginx:1.27
        ports:
        - containerPort: 80
        volumeMounts:
        - name: metrics
          mountPath: /var/metrics
        lifecycle:
          postStart:
            exec:
              command:
              - sh
              - -c
              - |
                # 메트릭 파일 생성
                while true; do
                  echo "app_requests_total $(( RANDOM % 1000 ))" > /var/metrics/metrics.txt
                  sleep 5
                done &
      
      # 사이드카: Prometheus Exporter
      - name: metrics-exporter
        image: busybox
        ports:
        - containerPort: 9090
        volumeMounts:
        - name: metrics
          mountPath: /var/metrics
          readOnly: true
        command:
        - sh
        - -c
        - |
          # 간단한 HTTP 서버로 메트릭 노출
          while true; do
            echo -e "HTTP/1.1 200 OK\r\n\r\n$(cat /var/metrics/metrics.txt 2>/dev/null || echo 'no metrics')" | nc -l -p 9090
          done
```

## 실습 5: Ambassador 패턴 - Redis Proxy

**redis-with-proxy.yaml**:
```yaml
# Redis Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:6.2
        ports:
        - containerPort: 6379
---
# Redis Service
apiVersion: v1
kind: Service
metadata:
  name: redis
spec:
  type: ClusterIP
  ports:
  - port: 6379
  selector:
    app: redis
---
# App with Redis Ambassador
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-redis-proxy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-client
  template:
    metadata:
      labels:
        app: redis-client
    spec:
      containers:
      # 메인 애플리케이션 (localhost:6379로 Redis 접속)
      - name: app
        image: redis:6.2
        command:
        - sh
        - -c
        - |
          # localhost의 Redis에 접속 (실제로는 ambassador를 통함)
          while true; do
            redis-cli -h localhost PING
            sleep 5
          done
      
      # Ambassador: Redis 프록시
      - name: redis-proxy
        image: haproxy:2.4
        ports:
        - containerPort: 6379
        volumeMounts:
        - name: proxy-config
          mountPath: /usr/local/etc/haproxy
      
      volumes:
      - name: proxy-config
        configMap:
          name: redis-proxy-config
---
# HAProxy 설정
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-proxy-config
data:
  haproxy.cfg: |
    global
        maxconn 256
    
    defaults
        mode tcp
        timeout connect 5000ms
        timeout client 50000ms
        timeout server 50000ms
    
    frontend redis-in
        bind *:6379
        default_backend redis-backend
    
    backend redis-backend
        server redis1 redis:6379 check
```

**배포**:
```bash
kubectl apply -f redis-with-proxy.yaml

# 로그 확인 (app이 localhost:6379로 연결)
POD_NAME=$(kubectl get pod -l app=redis-client -o jsonpath='{.items[0].metadata.name}')
kubectl logs $POD_NAME -c app
```

## Multi-Container 통신 방법

### 1. Localhost 통신

같은 Pod의 컨테이너는 `localhost`로 통신:

```yaml
containers:
- name: app
  image: myapp
  # localhost:8080으로 다른 컨테이너 접근

- name: proxy
  image: nginx
  ports:
  - containerPort: 8080
```

### 2. 공유 볼륨

```yaml
volumes:
- name: shared-data
  emptyDir: {}

containers:
- name: writer
  volumeMounts:
  - name: shared-data
    mountPath: /data

- name: reader
  volumeMounts:
  - name: shared-data
    mountPath: /data
    readOnly: true
```

### 3. IPC (Inter-Process Communication)

```yaml
spec:
  shareProcessNamespace: true  # 프로세스 네임스페이스 공유
  containers:
  - name: app1
  - name: app2
```

## Multi-Container 디버깅

### 특정 컨테이너 로그 확인

```bash
# 컨테이너별 로그
kubectl logs <pod-name> -c <container-name>

# 모든 컨테이너 로그
kubectl logs <pod-name> --all-containers=true

# 실시간 로그
kubectl logs <pod-name> -c <container-name> -f
```

### 특정 컨테이너에 접속

```bash
# 컨테이너 셸 접속
kubectl exec -it <pod-name> -c <container-name> -- /bin/bash

# 명령어 실행
kubectl exec <pod-name> -c <container-name> -- ls -la /data
```

### 컨테이너 상태 확인

```bash
# 모든 컨테이너 상태
kubectl get pod <pod-name> -o jsonpath='{.status.containerStatuses[*]}' | jq .

# 준비되지 않은 컨테이너 찾기
kubectl get pod <pod-name> -o jsonpath='{.status.containerStatuses[?(@.ready==false)].name}'
```

## 베스트 프랙티스

### 1. 컨테이너 역할 명확화

```yaml
# ✅ 좋은 예: 명확한 역할
containers:
- name: app        # 메인 애플리케이션
- name: logger     # 로그 수집
- name: metrics    # 메트릭 노출

# ❌ 나쁜 예: 모호한 역할
containers:
- name: container1
- name: container2
```

### 2. 리소스 제한 설정

각 컨테이너에 적절한 리소스 할당:

```yaml
containers:
- name: app
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1Gi

- name: sidecar
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi
```

### 3. 의존성 순서 고려

Init Container를 사용하여 순서 보장:

```yaml
initContainers:
- name: wait-for-db
  # DB 연결 대기

containers:
- name: app
  # DB가 준비된 후 시작
```

### 4. 볼륨 마운트 권한

읽기 전용 마운트 활용:

```yaml
volumeMounts:
- name: config
  mountPath: /etc/config
  readOnly: true  # ✅ 수정 방지
```

## 정리

```bash
# Deployment 삭제
kubectl delete deploy nginx-with-sidecar multi-dep multi-dep-fixed \
  app-with-exporter redis app-with-redis-proxy

# Service 삭제
kubectl delete svc nginx-with-sidecar redis

# ConfigMap 삭제
kubectl delete cm redis-proxy-config
```

## 실습 과제

1. **Sidecar 로깅**
   - Nginx + 로그 수집 사이드카 구성
   - 공유 볼륨으로 로그 파일 공유

2. **문제 분석**
   - 의도적으로 오류가 있는 Multi-Container Pod 배포
   - 각 컨테이너의 문제 진단 및 수정

3. **Ambassador 패턴**
   - 외부 서비스 프록시 구현
   - localhost로 접근하는 앱 작성

4. **메트릭 수집**
   - 메인 앱 + Prometheus Exporter 사이드카
   - 메트릭 노출 확인

## 다음 단계

다음 섹션에서는 [Jobs와 CronJobs](./jobs)를 통한 배치 작업 스케줄링을 학습합니다.

## 참고 자료

- [Multi-Container Pod 패턴](https://kubernetes.io/blog/2015/06/the-distributed-system-toolkit-patterns/)
- [Sidecar 패턴](https://kubernetes.io/docs/concepts/workloads/pods/#how-pods-manage-multiple-containers)
- [Service Mesh Sidecar](https://istio.io/latest/docs/concepts/traffic-management/)
