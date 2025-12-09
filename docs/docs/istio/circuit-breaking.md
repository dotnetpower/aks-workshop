# Circuit Breaking

Circuit Breaking을 통해 서비스 간 연결을 관리하고 장애 전파를 방지하는 방법을 실습합니다.

## 개요

Circuit Breaking은 연결 풀과 요청 제한을 설정하여 서비스의 안정성을 높입니다.

참고: [Istio Circuit Breaking 공식 문서](https://istio.io/latest/docs/tasks/traffic-management/circuit-breaking/)

## httpbin 서비스 구성

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/httpbin/httpbin.yaml -n bookinfo
```

## DestinationRule 설정

최대 연결 수와 요청 수를 제한하는 Circuit Breaking 정책을 설정합니다:

```bash
kubectl apply -n bookinfo -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: httpbin
spec:
  host: httpbin
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1
      http:
        http1MaxPendingRequests: 1
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 1
      interval: 1s
      baseEjectionTime: 3m
      maxEjectionPercent: 100
EOF
```

### 설정 설명

- `maxConnections: 1`: 최대 TCP 연결 수를 1개로 제한
- `http1MaxPendingRequests: 1`: 대기 중인 HTTP 요청을 1개로 제한
- `maxRequestsPerConnection: 1`: 연결당 최대 요청 수를 1개로 제한
- `consecutive5xxErrors: 1`: 연속 5xx 오류가 1번 발생하면 호스트를 제외
- `baseEjectionTime: 3m`: 제외된 호스트가 3분 동안 로드 밸런싱에서 제외됨

### 설정 확인

```bash
kubectl get destinationrule httpbin -n bookinfo -o yaml
```

## fortio 부하 테스트 도구 구성

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/httpbin/sample-client/fortio-deploy.yaml -n bookinfo

export FORTIO_POD=$(kubectl get pods -l app=fortio -n bookinfo -o jsonpath='{.items[0].metadata.name}')
```

### 단순 요청 테스트

```bash
kubectl exec $FORTIO_POD -c fortio -n bookinfo -- /usr/bin/fortio curl -quiet http://httpbin:8000/get
```

## Circuit Breaking 테스트

2개의 동시 연결로 20번 요청을 보냅니다:

```bash
kubectl exec $FORTIO_POD -c fortio -n bookinfo -- /usr/bin/fortio load -c 2 -qps 0 -n 20 -loglevel Warning http://httpbin:8000/get
```

### 예상 결과

`maxRequestsPerConnection`이 1로 설정되어 있어 동시 요청 2개 중 1개는 circuit breaking에 걸려 실패합니다.

출력에서 다음과 같은 정보를 확인할 수 있습니다:
- 성공한 요청 수
- Circuit breaking으로 인해 실패한 요청 수
- HTTP 503 (Service Unavailable) 응답

## 리소스 정리

### DestinationRule 삭제

```bash
kubectl delete destinationrule httpbin -n bookinfo
```

### httpbin 서비스와 클라이언트 제거

```bash
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/httpbin/sample-client/fortio-deploy.yaml -n bookinfo
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/httpbin/httpbin.yaml -n bookinfo
```

## 추가 실습

:::tip 실습 과제
1. `maxConnections`를 2로 변경하면 어떻게 되는지 테스트해보세요
2. 동시 연결 수를 3개로 늘려서 테스트해보세요
3. `consecutive5xxErrors`를 조정하여 서비스 제외 정책의 변화를 확인해보세요
:::
