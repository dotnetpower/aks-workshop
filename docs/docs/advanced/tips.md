# 상세 정보 및 유용한 팁

## Istio Mesh 상세 정보 확인

### Proxy 상태 확인

```bash
istioctl -i aks-istio-system proxy-status
```

출력 예시:
```
NAME                                                                              CLUSTER        CDS        LDS        EDS        RDS        ECDS         ISTIOD                               VERSION
aks-istio-ingressgateway-external-asm-1-18-7466f77bb9-2bx8x.aks-istio-ingress     Kubernetes     SYNCED     SYNCED     SYNCED     SYNCED     NOT SENT     istiod-asm-1-18-746d8f469c-mttxb     1.18.7-distroless
details-v1-7c7dbcb4b5-prwmr.bookinfo                                              Kubernetes     SYNCED     SYNCED     SYNCED     SYNCED     NOT SENT     istiod-asm-1-18-746d8f469c-bvl92     1.18.7-distroless
productpage-v1-664d44d68d-hx9dw.bookinfo                                          Kubernetes     SYNCED     SYNCED     SYNCED     SYNCED     NOT SENT     istiod-asm-1-18-746d8f469c-bvl92     1.18.7-distroless
```

### 사이드카 인젝션 정보 확인

```bash
PRODUCTPAGE_POD=$(kubectl get pods -n bookinfo | grep ^productpage | awk '{print $1}')
istioctl -i aks-istio-system experimental check-inject $PRODUCTPAGE_POD -n bookinfo
```

### Pod 상세 정보 확인

```bash
istioctl -i aks-istio-system experimental describe pod $PRODUCTPAGE_POD -n bookinfo
```

### Envoy Endpoint 확인

```bash
istioctl -i aks-istio-system proxy-config endpoint $PRODUCTPAGE_POD -n bookinfo
```

## VS Code Remote 환경 설정

### 포트 포워딩 관리

VS Code의 Ports 탭을 활용하여 로컬 환경에서 원격 서비스에 접속:

1. VS Code에서 하단의 "PORTS" 탭 선택
2. "Forward a Port" 버튼 클릭
3. 포트 번호 입력 (예: 20001, 9090, 3000, 16686)
4. 로컬 브라우저에서 `localhost:<port>` 로 접속

## Bash 환경 설정

### 타임스탬프 추가

```bash
# Bash 커맨드 창에 시간 찍기
sudo timedatectl set-timezone Asia/Seoul
export PROMPT_COMMAND="echo -n \[\$(date +%H:%M:%S)\]\ "
```

### 현재 클러스터 표시

```bash
# 현재 클러스터를 커맨드 창 앞에 붙이기
export PROMPT_COMMAND="echo -n [$CLUSTER]"
```

### 영구 설정

`.bashrc` 파일에 추가하여 영구적으로 설정:

```bash
echo 'export PROMPT_COMMAND="echo -n [$CLUSTER]"' >> ~/.bashrc
source ~/.bashrc
```

## 유용한 kubectl 명령어

### 리소스 모니터링

```bash
# 모든 네임스페이스의 Pod 확인
kubectl get pods --all-namespaces

# 특정 네임스페이스의 모든 리소스 확인
kubectl get all -n bookinfo

# 리소스 사용량 확인
kubectl top nodes
kubectl top pods -n bookinfo
```

### 로그 확인

```bash
# Pod 로그 확인
kubectl logs <pod-name> -n bookinfo

# 사이드카 로그 확인
kubectl logs <pod-name> -c istio-proxy -n bookinfo

# 실시간 로그 스트리밍
kubectl logs -f <pod-name> -n bookinfo
```

### 디버깅

```bash
# Pod 내부 접속
kubectl exec -it <pod-name> -n bookinfo -- /bin/bash

# 특정 컨테이너 접속
kubectl exec -it <pod-name> -c <container-name> -n bookinfo -- /bin/bash

# Pod 상세 정보
kubectl describe pod <pod-name> -n bookinfo
```

## Istio 리소스 확인

```bash
# VirtualService 확인
kubectl get virtualservices -n bookinfo
kubectl describe virtualservice <vs-name> -n bookinfo

# DestinationRule 확인
kubectl get destinationrules -n bookinfo
kubectl describe destinationrule <dr-name> -n bookinfo

# Gateway 확인
kubectl get gateways -n bookinfo
kubectl describe gateway <gateway-name> -n bookinfo

# AuthorizationPolicy 확인
kubectl get authorizationpolicies -n bookinfo
kubectl describe authorizationpolicy <policy-name> -n bookinfo
```

## 트러블슈팅

### 일반적인 문제

1. **Pod가 Pending 상태**: 
   ```bash
   kubectl describe pod <pod-name> -n bookinfo
   ```
   리소스 부족 또는 노드 스케줄링 문제 확인

2. **사이드카 인젝션 안됨**:
   ```bash
   kubectl get namespace bookinfo --show-labels
   ```
   네임스페이스 라벨 확인

3. **서비스 연결 실패**:
   ```bash
   istioctl analyze -n bookinfo
   ```
   구성 오류 확인

### Istio 구성 검증

```bash
# 전체 구성 검증
istioctl analyze --all-namespaces

# 특정 네임스페이스 검증
istioctl analyze -n bookinfo
```

## 성능 튜닝

### Envoy 프록시 리소스 조정

```yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    sidecar.istio.io/proxyCPU: "100m"
    sidecar.istio.io/proxyMemory: "128Mi"
    sidecar.istio.io/proxyCPULimit: "2000m"
    sidecar.istio.io/proxyMemoryLimit: "1024Mi"
```

### 연결 풀 설정

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: reviews-cb-policy
spec:
  host: reviews
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 1
        http2MaxRequests: 100
        maxRequestsPerConnection: 2
```
