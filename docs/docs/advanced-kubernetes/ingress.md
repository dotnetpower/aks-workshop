# Ingress Controller

Ingress는 클러스터 외부에서 내부 서비스로의 HTTP/HTTPS 트래픽을 라우팅하는 API 객체입니다. Ingress Controller는 Ingress 규칙을 실제로 처리하는 컴포넌트로, AKS에서는 주로 Nginx Ingress Controller를 사용합니다.

## Ingress의 필요성

### Service LoadBalancer의 한계

각 서비스마다 LoadBalancer를 사용하면:
- ❌ 각 서비스마다 외부 IP 필요 (비용 증가)
- ❌ 여러 개의 Azure Load Balancer 생성
- ❌ URL 경로 기반 라우팅 불가
- ❌ SSL/TLS 종료 기능 제한적

### Ingress의 장점

- ✅ 단일 외부 IP로 여러 서비스 제공
- ✅ 경로 기반 라우팅 (`/api`, `/web`, `/admin`)
- ✅ 호스트 기반 라우팅 (도메인별 라우팅)
- ✅ SSL/TLS 종료 중앙 관리
- ✅ 리다이렉션, 리라이트 등 고급 기능

## 아키텍처

```
인터넷
   ↓
Azure Load Balancer (단일 공인 IP)
   ↓
Ingress Controller (Nginx Pod)
   ↓
Ingress 규칙 적용
   ↓
내부 Service (ClusterIP)
   ↓
Pod
```

## Nginx Ingress Controller 설치

### Helm을 사용한 설치

**1. Helm 리포지토리 추가**:
```bash
# Helm 설치 확인
helm version

# Nginx Ingress Controller 리포지토리 추가
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

**2. Nginx Ingress Controller 설치**:
```bash
# 네임스페이스 생성
kubectl create namespace ingress-nginx

# Nginx Ingress Controller 설치
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
  --set controller.replicaCount=2
```

**3. 설치 확인**:
```bash
# Pod 확인
kubectl get pods -n ingress-nginx

# Service 확인 (외부 IP 할당 대기)
kubectl get svc -n ingress-nginx
```

**외부 IP 확인**:
```bash
# EXTERNAL-IP가 할당될 때까지 대기
kubectl get svc ingress-nginx-controller -n ingress-nginx -w

# 외부 IP 저장
INGRESS_IP=$(kubectl get svc ingress-nginx-controller \
  -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Ingress Controller IP: $INGRESS_IP"
```

**기본 동작 확인**:
```bash
# 브라우저 또는 curl로 접근
curl http://$INGRESS_IP
```

**결과**: `404 Not Found` - 정상입니다! 아직 Ingress 규칙이 없기 때문입니다.

## 실습 1: 기본 Ingress 라우팅

### 애플리케이션 배포

**1. 개발 네임스페이스 생성**:
```bash
kubectl create namespace development
```

**2. Blue 애플리케이션 배포**:

**blue-dep.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blue-dep
  namespace: development
spec:
  replicas: 2
  selector:
    matchLabels:
      app: blue
  template:
    metadata:
      labels:
        app: blue
    spec:
      containers:
      - name: nginx
        image: nginx:1.18
        ports:
        - containerPort: 80
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      initContainers:
      - name: install
        image: busybox
        command:
        - sh
        - -c
        - |
          echo '<html><body style="background-color:blue;"><h1>Blue Application</h1></body></html>' > /work-dir/index.html
        volumeMounts:
        - name: html
          mountPath: /work-dir
      volumes:
      - name: html
        emptyDir: {}
```

**blue-svc-cip.yaml**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: blue-svc
  namespace: development
spec:
  type: ClusterIP  # 내부용 (Ingress를 통해서만 접근)
  ports:
  - port: 8100
    targetPort: 80
  selector:
    app: blue
```

**3. Red와 Yellow 애플리케이션 배포**:

**red-dep.yaml** (blue-dep.yaml과 유사하게 red로 변경):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: red-dep
  namespace: development
spec:
  replicas: 2
  selector:
    matchLabels:
      app: red
  template:
    metadata:
      labels:
        app: red
    spec:
      containers:
      - name: nginx
        image: nginx:1.18
        ports:
        - containerPort: 80
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      initContainers:
      - name: install
        image: busybox
        command:
        - sh
        - -c
        - |
          echo '<html><body style="background-color:red;"><h1>Red Application</h1></body></html>' > /work-dir/index.html
        volumeMounts:
        - name: html
          mountPath: /work-dir
      volumes:
      - name: html
        emptyDir: {}
```

**red-svc-cip.yaml**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: red-svc
  namespace: development
spec:
  type: ClusterIP
  ports:
  - port: 8100
    targetPort: 80
  selector:
    app: red
```

**yellow-dep.yaml와 yellow-svc-cip.yaml도 유사하게 생성**

**배포**:
```bash
kubectl apply -f blue-dep.yaml -f blue-svc-cip.yaml -n development
kubectl apply -f red-dep.yaml -f red-svc-cip.yaml -n development
kubectl apply -f yellow-dep.yaml -f yellow-svc-cip.yaml -n development

# 확인
kubectl get all -n development
```

### Ingress 규칙 생성

**colors-ingress.yaml**:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: colors-ingress
  namespace: development
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$1
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /blue/(.*)
        pathType: Prefix
        backend:
          service:
            name: blue-svc
            port:
              number: 8100
      - path: /red/(.*)
        pathType: Prefix
        backend:
          service:
            name: red-svc
            port:
              number: 8100
      - path: /yellow/(.*)
        pathType: Prefix
        backend:
          service:
            name: yellow-svc
            port:
              number: 8100
```

**annotations 설명**:
- `rewrite-target: /$1`: URL 경로를 재작성
  - 예: `/blue/test` → `/test` (백엔드 서비스로 전달)
  - `(.*)`: 경로의 나머지 부분을 캡처
  - `$1`: 캡처한 부분으로 대체

**배포 및 테스트**:
```bash
# Ingress 생성
kubectl apply -f colors-ingress.yaml

# Ingress 확인
kubectl get ingress -n development

# 각 경로 테스트
curl http://$INGRESS_IP/blue/
curl http://$INGRESS_IP/red/
curl http://$INGRESS_IP/yellow/
```

**브라우저로 확인**:
- `http://<INGRESS_IP>/blue/` - 파란색 화면
- `http://<INGRESS_IP>/red/` - 빨간색 화면
- `http://<INGRESS_IP>/yellow/` - 노란색 화면

## 실습 2: 네임스페이스별 Ingress

여러 환경(개발, 스테이징, 프로덕션)을 네임스페이스로 분리하고 각각 Ingress를 구성할 수 있습니다.

### 스테이징 환경 구성

**1. 스테이징 네임스페이스 생성**:
```bash
kubectl create namespace staging
```

**2. 스테이징 애플리케이션 배포**:
```bash
# development의 리소스를 staging으로 복사
kubectl apply -f blue-dep.yaml -f blue-svc-cip.yaml -n staging
kubectl apply -f red-dep.yaml -f red-svc-cip.yaml -n staging
kubectl apply -f yellow-dep.yaml -f yellow-svc-cip.yaml -n staging
```

### 환경별 Ingress 규칙

**colors-ingress-development.yaml**:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: colors-ingress
  namespace: development
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /development/blue(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: blue-svc
            port:
              number: 8100
      - path: /development/red(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: red-svc
            port:
              number: 8100
      - path: /development/yellow(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: yellow-svc
            port:
              number: 8100
```

**colors-ingress-staging.yaml**:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: colors-ingress
  namespace: staging
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /staging/blue(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: blue-svc
            port:
              number: 8100
      - path: /staging/red(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: red-svc
            port:
              number: 8100
      - path: /staging/yellow(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: yellow-svc
            port:
              number: 8100
```

**배포 및 테스트**:
```bash
# 기존 Ingress 삭제
kubectl delete ingress colors-ingress -n development

# 새 Ingress 생성
kubectl apply -f colors-ingress-development.yaml
kubectl apply -f colors-ingress-staging.yaml

# 확인
kubectl get ingress -n development
kubectl get ingress -n staging

# 테스트
curl http://$INGRESS_IP/development/blue/
curl http://$INGRESS_IP/staging/blue/
```

## 실습 3: Default Backend 설정

정의되지 않은 경로로 접근 시 커스텀 404 페이지를 제공할 수 있습니다.

### Default Backend 애플리케이션

**default-dep.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: default-dep
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: default-backend
  template:
    metadata:
      labels:
        app: default-backend
    spec:
      containers:
      - name: nginx
        image: nginx:1.18
        ports:
        - containerPort: 80
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      initContainers:
      - name: install
        image: busybox
        command:
        - sh
        - -c
        - |
          cat > /work-dir/index.html <<EOF
          <html>
          <head><title>404 Not Found</title></head>
          <body>
          <h1>404 - Page Not Found</h1>
          <p>The requested page does not exist.</p>
          <p>Available paths:</p>
          <ul>
            <li>/development/blue/</li>
            <li>/development/red/</li>
            <li>/staging/blue/</li>
          </ul>
          </body>
          </html>
          EOF
        volumeMounts:
        - name: html
          mountPath: /work-dir
      volumes:
      - name: html
        emptyDir: {}
```

**default-svc.yaml**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: default-svc
  namespace: default
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: default-backend
```

**default-backend.yaml**:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: default-ingress-backend
  namespace: default
spec:
  ingressClassName: nginx
  defaultBackend:
    service:
      name: default-svc
      port:
        number: 80
```

**배포**:
```bash
kubectl apply -f default-dep.yaml
kubectl apply -f default-svc.yaml
kubectl apply -f default-backend.yaml

# 테스트 (존재하지 않는 경로)
curl http://$INGRESS_IP/
curl http://$INGRESS_IP/notfound
```

커스텀 404 페이지가 표시됩니다!

## 고급 Ingress 기능

### 1. 호스트 기반 라우팅

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: host-based-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: blue.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: blue-svc
            port:
              number: 8100
  - host: red.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: red-svc
            port:
              number: 8100
```

### 2. TLS/SSL 종료

**시크릿 생성 (self-signed 인증서)**:
```bash
# 자체 서명 인증서 생성
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=example.com/O=example"

# TLS Secret 생성
kubectl create secret tls tls-secret \
  --cert=tls.crt --key=tls.key \
  -n development
```

**TLS Ingress**:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tls-ingress
  namespace: development
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - example.com
    secretName: tls-secret
  rules:
  - host: example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: blue-svc
            port:
              number: 8100
```

### 3. Rate Limiting

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rate-limit-ingress
  annotations:
    nginx.ingress.kubernetes.io/limit-rps: "10"  # 초당 10개 요청
    nginx.ingress.kubernetes.io/limit-connections: "5"  # 동시 연결 5개
spec:
  # ... rules
```

### 4. Redirect (HTTP → HTTPS)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: redirect-ingress
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  # ... rules
```

### 5. Custom Headers

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: custom-header-ingress
  annotations:
    nginx.ingress.kubernetes.io/configuration-snippet: |
      add_header X-Custom-Header "My Value" always;
      add_header X-Environment "Development" always;
spec:
  # ... rules
```

### 6. CORS 설정

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: cors-ingress
  annotations:
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "*"
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, PUT, DELETE, OPTIONS"
spec:
  # ... rules
```

## PathType 이해

| PathType | 설명 | 예시 |
|----------|------|------|
| `Exact` | 정확히 일치하는 경로만 | `/blue` ✅, `/blue/` ❌ |
| `Prefix` | 접두사가 일치하는 모든 경로 | `/blue`, `/blue/`, `/blue/test` 모두 ✅ |
| `ImplementationSpecific` | Ingress Controller에 따라 다름 | - |

## Ingress 모니터링

### Ingress 상태 확인

```bash
# Ingress 목록
kubectl get ingress --all-namespaces

# 상세 정보
kubectl describe ingress colors-ingress -n development

# Ingress Controller 로그
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

### 요청 테스트

```bash
# 헤더 포함하여 확인
curl -v http://$INGRESS_IP/development/blue/

# 호스트 헤더 지정
curl -H "Host: example.com" http://$INGRESS_IP/
```

## 정리

```bash
# 네임스페이스별 리소스 삭제
kubectl delete namespace development
kubectl delete namespace staging

# Default backend 삭제
kubectl delete deploy default-dep -n default
kubectl delete svc default-svc -n default
kubectl delete ingress default-ingress-backend -n default

# Ingress Controller 삭제 (필요시)
helm uninstall ingress-nginx -n ingress-nginx
kubectl delete namespace ingress-nginx
```

## 베스트 프랙티스

1. **단일 Ingress Controller 사용**
   - 클러스터당 하나의 Ingress Controller 권장
   - 비용 절감 및 관리 효율성

2. **네임스페이스별 Ingress 분리**
   - 환경별 격리 (dev, staging, prod)
   - 각 네임스페이스에 별도 Ingress 규칙

3. **경로 설계**
   - 명확하고 일관된 URL 구조
   - `/api/v1`, `/web`, `/admin` 등

4. **TLS/SSL 적용**
   - 프로덕션 환경에서는 항상 HTTPS 사용
   - Let's Encrypt와 cert-manager 통합

5. **Rate Limiting 설정**
   - DDoS 공격 방지
   - 리소스 보호

6. **모니터링 및 로깅**
   - Ingress Controller 로그 수집
   - 메트릭 모니터링 (프로메테우스)

## 실습 과제

1. **기본 Ingress 구성**
   - 3개의 서로 다른 애플리케이션 배포
   - 경로 기반 라우팅으로 Ingress 구성

2. **네임스페이스별 라우팅**
   - dev, staging 네임스페이스 생성
   - 각 환경별로 `/dev/app`, `/staging/app` 경로 구성

3. **TLS 적용**
   - 자체 서명 인증서 생성
   - HTTPS Ingress 구성 및 테스트

4. **Default Backend**
   - 커스텀 404 페이지 생성
   - Default Backend 설정

## 다음 단계

다음 섹션에서는 [헬스 체크](./probes)를 통한 애플리케이션 안정성 향상 방법을 학습합니다.

## 참고 자료

- [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Nginx Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [AKS에서 Ingress Controller 만들기](https://learn.microsoft.com/ko-kr/azure/aks/ingress-basic)
- [cert-manager로 HTTPS 설정](https://cert-manager.io/docs/)
