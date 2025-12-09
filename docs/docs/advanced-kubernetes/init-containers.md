# Init Container

Init Container는 애플리케이션 컨테이너가 시작되기 전에 실행되는 특수한 컨테이너입니다. 초기화 작업, 설정 파일 준비, 데이터 마이그레이션 등의 작업을 수행하는 데 사용됩니다.

## Init Container의 특징

### 기본 특징

1. **순차적 실행**
   - 여러 Init Container가 있는 경우 순서대로 실행
   - 이전 Init Container가 성공해야 다음이 실행됨

2. **완료 후 종료**
   - 작업 완료 후 종료 (계속 실행되지 않음)
   - 모든 Init Container가 성공해야 앱 컨테이너 시작

3. **재시작 정책**
   - 실패 시 Pod의 `restartPolicy`에 따라 재시작
   - `Always`, `OnFailure`: Init Container 재실행
   - `Never`: Pod 실패

4. **리소스 격리**
   - Init Container와 앱 컨테이너는 별도의 리소스 사용
   - 완료 후 리소스 해제

### 일반 컨테이너와의 차이점

| 구분 | Init Container | App Container |
|------|---------------|---------------|
| 실행 시점 | Pod 시작 시 (앱 컨테이너 전) | Init Container 완료 후 |
| 실행 방식 | 순차적 | 동시 |
| 라이프사이클 | 완료 후 종료 | 계속 실행 |
| Readiness Probe | 지원 안 함 | 지원 |
| Lifecycle Hook | 지원 안 함 | 지원 |

## 사용 사례

### 1. 데이터 준비 및 다운로드

- 설정 파일 다운로드
- 정적 콘텐츠 가져오기
- Git 리포지토리 클론

### 2. 의존성 대기

- 데이터베이스 연결 대기
- 다른 서비스가 준비될 때까지 대기
- 외부 API 가용성 확인

### 3. 환경 설정

- 설정 파일 생성 및 변환
- 템플릿에서 실제 설정 생성
- 권한 및 소유권 설정

### 4. 마이그레이션 및 초기화

- 데이터베이스 스키마 마이그레이션
- 캐시 워밍업
- 초기 데이터 로딩

## 실습 1: 기본 Init Container

### 간단한 카운터 Init Container

**init-dep.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: init-dep
spec:
  replicas: 1
  selector:
    matchLabels:
      app: init-1
  template:
    metadata:
      labels:
        app: init-1
        color: orange
    spec:
      # Init Containers: 순서대로 실행
      initContainers:
      # 1. 카운터 Init Container (15초 대기)
      - name: counter-init
        image: centos:7
        command:
        - "bin/bash"
        - "-c"
        - "for i in {1..15}; do echo $i; sleep 1s; done"
      
      # 2. 웹 페이지 다운로드 Init Container
      - name: homepage
        image: busybox
        args:
        - "/bin/sh"
        - "-c"
        - "wget -O /work-dir/index.html http://neverssl.com/online; sleep 10s;"
        volumeMounts:
        - name: tempvol
          mountPath: /work-dir
      
      # App Containers: Init Container 완료 후 시작
      containers:
      # 1. Nginx 컨테이너 (다운로드한 페이지 서빙)
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
          protocol: TCP
        volumeMounts:
        - name: tempvol
          mountPath: /usr/share/nginx/html
      
      # 2. MySQL 컨테이너
      - name: mysql
        image: mysql:5.7
        env:
        - name: MYSQL_ALLOW_EMPTY_PASSWORD
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
      
      # 3. 카운터 컨테이너
      - name: counter
        image: centos:7
        command:
        - "bin/bash"
        - "-c"
        - "for i in {1..999}; do echo $i; sleep 1; done"
      
      volumes:
      - name: tempvol
        emptyDir: {}  # Init Container와 앱 컨테이너 간 데이터 공유
```

**배포 및 관찰**:
```bash
# Deployment 생성
kubectl apply -f init-dep.yaml

# Pod 상태 실시간 확인
kubectl get pods -l app=init-1 -w
```

**Pod 상태 변화**:
```
NAME                        READY   STATUS     RESTARTS   AGE
init-dep-xxxx               0/3     Init:0/2   0          5s
init-dep-xxxx               0/3     Init:1/2   0          15s
init-dep-xxxx               0/3     Init:1/2   0          25s
init-dep-xxxx               0/3     PodInitializing   0   26s
init-dep-xxxx               3/3     Running    0          30s
```

**상태 설명**:
- `Init:0/2`: 첫 번째 Init Container 실행 중 (2개 중 0개 완료)
- `Init:1/2`: 두 번째 Init Container 실행 중 (2개 중 1개 완료)
- `PodInitializing`: Init Container 완료, 앱 컨테이너 시작 중
- `Running`: 모든 컨테이너 실행 중

### Pod 세부 정보 확인

```bash
POD_NAME=$(kubectl get pod -l app=init-1 -o jsonpath='{.items[0].metadata.name}')

# Pod 상세 정보
kubectl describe pod $POD_NAME
```

**Init Container 섹션**:
```yaml
Init Containers:
  counter-init:
    Container ID:  containerd://...
    Image:         centos:7
    State:         Terminated
      Reason:      Completed
      Exit Code:   0
  
  homepage:
    Container ID:  containerd://...
    Image:         busybox
    State:         Terminated
      Reason:      Completed
      Exit Code:   0
```

### Init Container 로그 확인

```bash
# 첫 번째 Init Container 로그
kubectl logs $POD_NAME -c counter-init

# 두 번째 Init Container 로그
kubectl logs $POD_NAME -c homepage
```

### 다운로드된 페이지 확인

```bash
# Nginx 컨테이너에서 페이지 확인
kubectl exec $POD_NAME -c nginx -- cat /usr/share/nginx/html/index.html

# Service 생성 후 브라우저에서 확인
kubectl expose deployment init-dep --type=LoadBalancer --port=80

# 외부 IP 확인
kubectl get svc init-dep
```

## 실습 2: 의존성 대기 Init Container

데이터베이스가 준비될 때까지 대기하는 Init Container를 구성합니다.

### MySQL과 웹 앱 배포

**mysql-app.yaml**:
```yaml
# MySQL Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:5.7
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: "password"
        - name: MYSQL_DATABASE
          value: "myapp"
        ports:
        - containerPort: 3306
---
# MySQL Service
apiVersion: v1
kind: Service
metadata:
  name: mysql
spec:
  type: ClusterIP
  ports:
  - port: 3306
  selector:
    app: mysql
---
# Web App with Init Container
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
    spec:
      # MySQL 연결 대기 Init Container
      initContainers:
      - name: wait-for-mysql
        image: busybox:1.28
        command:
        - 'sh'
        - '-c'
        - |
          echo "Waiting for MySQL to be ready..."
          until nc -z mysql 3306; do
            echo "MySQL is not ready yet..."
            sleep 2
          done
          echo "MySQL is ready!"
      
      # 앱 컨테이너
      containers:
      - name: app
        image: nginx:1.27
        ports:
        - containerPort: 80
```

**배포 및 테스트**:
```bash
# MySQL과 웹앱 배포
kubectl apply -f mysql-app.yaml

# Pod 상태 확인
kubectl get pods -l app=webapp -w
```

**관찰**:
- Init Container가 MySQL 서비스가 준비될 때까지 대기
- MySQL Pod가 준비되면 Init Container 완료
- 웹앱 컨테이너 시작

## 실습 3: 설정 파일 생성 Init Container

### ConfigMap에서 설정 파일 생성

**config-init.yaml**:
```yaml
# ConfigMap with template
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-template
data:
  app.conf.tmpl: |
    server {
        listen 80;
        server_name ${HOSTNAME};
        
        location / {
            root /usr/share/nginx/html;
            index index.html;
        }
        
        location /api {
            proxy_pass http://${API_SERVICE}:${API_PORT};
        }
    }
---
# Deployment with config generation
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-config
spec:
  replicas: 1
  selector:
    matchLabels:
      app: config-app
  template:
    metadata:
      labels:
        app: config-app
    spec:
      initContainers:
      # 설정 파일 생성 Init Container
      - name: generate-config
        image: busybox
        env:
        - name: HOSTNAME
          value: "myapp.example.com"
        - name: API_SERVICE
          value: "api-service"
        - name: API_PORT
          value: "8080"
        command:
        - sh
        - -c
        - |
          echo "Generating config file..."
          # 환경 변수를 실제 값으로 치환
          cat /config-template/app.conf.tmpl | \
            sed "s/\${HOSTNAME}/$HOSTNAME/g" | \
            sed "s/\${API_SERVICE}/$API_SERVICE/g" | \
            sed "s/\${API_PORT}/$API_PORT/g" \
            > /config/app.conf
          echo "Config file generated:"
          cat /config/app.conf
        volumeMounts:
        - name: config-template
          mountPath: /config-template
        - name: config
          mountPath: /config
      
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
        volumeMounts:
        - name: config
          mountPath: /etc/nginx/conf.d
      
      volumes:
      - name: config-template
        configMap:
          name: app-config-template
      - name: config
        emptyDir: {}
```

**배포 및 확인**:
```bash
# 배포
kubectl apply -f config-init.yaml

# Init Container 로그 확인 (생성된 설정 파일)
POD_NAME=$(kubectl get pod -l app=config-app -o jsonpath='{.items[0].metadata.name}')
kubectl logs $POD_NAME -c generate-config

# 실행 중인 컨테이너에서 설정 파일 확인
kubectl exec $POD_NAME -- cat /etc/nginx/conf.d/app.conf
```

## 실습 4: Git 리포지토리 클론

### Git에서 정적 사이트 클론

**git-init.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: static-site
spec:
  replicas: 1
  selector:
    matchLabels:
      app: static-site
  template:
    metadata:
      labels:
        app: static-site
    spec:
      initContainers:
      # Git 리포지토리 클론
      - name: git-clone
        image: alpine/git
        args:
        - clone
        - --single-branch
        - --depth=1
        - https://github.com/your-org/your-static-site.git
        - /data
        volumeMounts:
        - name: site-data
          mountPath: /data
      
      # 권한 설정
      - name: set-permissions
        image: busybox
        command:
        - sh
        - -c
        - |
          echo "Setting permissions..."
          chmod -R 755 /data
          ls -la /data
        volumeMounts:
        - name: site-data
          mountPath: /data
      
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
        volumeMounts:
        - name: site-data
          mountPath: /usr/share/nginx/html
          readOnly: true
      
      volumes:
      - name: site-data
        emptyDir: {}
```

## 실습 5: 데이터베이스 마이그레이션

### 스키마 마이그레이션 Init Container

**db-migration.yaml**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: db-migrations
data:
  init.sql: |
    CREATE TABLE IF NOT EXISTS users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(50) NOT NULL,
        email VARCHAR(100) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    INSERT INTO users (username, email) VALUES
    ('admin', 'admin@example.com'),
    ('user1', 'user1@example.com');
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-migration
spec:
  replicas: 1
  selector:
    matchLabels:
      app: migration-app
  template:
    metadata:
      labels:
        app: migration-app
    spec:
      initContainers:
      # 데이터베이스 마이그레이션
      - name: db-migration
        image: mysql:5.7
        command:
        - sh
        - -c
        - |
          echo "Waiting for MySQL..."
          until mysql -h mysql -u root -ppassword -e "SELECT 1"; do
            sleep 2
          done
          
          echo "Running migrations..."
          mysql -h mysql -u root -ppassword myapp < /migrations/init.sql
          
          echo "Migration completed!"
        volumeMounts:
        - name: migrations
          mountPath: /migrations
      
      containers:
      - name: app
        image: nginx:1.27
        ports:
        - containerPort: 80
      
      volumes:
      - name: migrations
        configMap:
          name: db-migrations
```

## Init Container 디버깅

### 실패한 Init Container 확인

```bash
# Pod 상태 확인
kubectl get pods

# Pod 상세 정보 (이벤트 포함)
kubectl describe pod <pod-name>

# Init Container 로그 확인
kubectl logs <pod-name> -c <init-container-name>

# 이전 실행 로그 (재시작된 경우)
kubectl logs <pod-name> -c <init-container-name> --previous
```

### 일반적인 실패 원인

1. **명령어 오류**
   - 잘못된 경로, 오타
   - 권한 부족

2. **네트워크 문제**
   - 외부 리소스 다운로드 실패
   - DNS 해석 실패

3. **의존성 미준비**
   - 대기 중인 서비스가 시작되지 않음
   - 타임아웃 설정 부족

4. **리소스 부족**
   - CPU, 메모리 제한 초과
   - 스토리지 공간 부족

## Init Container 모범 사례

### 1. 적절한 이미지 선택

```yaml
# ✅ 좋은 예: 경량 이미지
initContainers:
- name: setup
  image: busybox  # 1-2MB
  
# ❌ 나쁜 예: 무거운 이미지
initContainers:
- name: setup
  image: ubuntu  # 70MB+
```

### 2. 타임아웃 설정

```yaml
initContainers:
- name: wait-for-service
  image: busybox
  command:
  - sh
  - -c
  - |
    timeout=60
    while [ $timeout -gt 0 ]; do
      if nc -z service 8080; then
        echo "Service is ready!"
        exit 0
      fi
      sleep 2
      timeout=$((timeout-2))
    done
    echo "Timeout waiting for service"
    exit 1
```

### 3. 명확한 로깅

```yaml
initContainers:
- name: setup
  image: busybox
  command:
  - sh
  - -c
  - |
    echo "Starting initialization..."
    echo "Step 1: Checking dependencies..."
    # ... 작업 수행
    echo "Step 2: Downloading resources..."
    # ... 작업 수행
    echo "Initialization completed successfully!"
```

### 4. 리소스 제한 설정

```yaml
initContainers:
- name: heavy-task
  image: myimage
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
```

### 5. 멱등성 보장

Init Container는 재시작될 수 있으므로 여러 번 실행해도 안전해야 합니다.

```yaml
initContainers:
- name: create-file
  image: busybox
  command:
  - sh
  - -c
  - |
    # ✅ 멱등성: 파일이 이미 있으면 건너뛰기
    if [ ! -f /data/initialized ]; then
      echo "Initializing..."
      # 초기화 작업
      touch /data/initialized
    else
      echo "Already initialized, skipping..."
    fi
```

## 정리

```bash
# Deployment 삭제
kubectl delete deploy init-dep app-with-config static-site app-with-migration webapp

# Service 삭제
kubectl delete svc init-dep mysql

# ConfigMap 삭제
kubectl delete cm app-config-template db-migrations
```

## 실습 과제

1. **기본 Init Container**
   - 2개의 Init Container를 가진 Pod 생성
   - 순차적 실행 확인

2. **의존성 대기**
   - 외부 서비스를 기다리는 Init Container 구현
   - 타임아웃 처리 추가

3. **설정 파일 생성**
   - ConfigMap 템플릿에서 실제 설정 파일 생성
   - 환경 변수를 사용한 동적 설정

4. **데이터 다운로드**
   - 웹에서 파일 다운로드하는 Init Container
   - 다운로드한 파일을 앱 컨테이너에서 사용

## 다음 단계

다음 섹션에서는 [Multi-Container Pods](./multi-container-pods)에서 사이드카 패턴과 멀티 컨테이너 설계를 학습합니다.

## 참고 자료

- [Init Containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
- [Init Container 디버깅](https://kubernetes.io/docs/tasks/debug-application-cluster/debug-init-containers/)
- [Init Container 사용 패턴](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/#what-can-init-containers-be-used-for)
