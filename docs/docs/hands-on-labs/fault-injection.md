# Fault Injection

특정 서비스에 예상치 못한 문제가 발생할 경우를 대비해 Fault 주입을 통해 서비스(애플리케이션)의 복원력을 테스트합니다.

## 개요

코드 변경 없이 Fault Injection 정의만으로 Resilience 테스트가 가능합니다.

## HTTP Delay Fault 주입

### 사전 준비

```bash
# 모든 요청을 v1으로만 흐르게 설정
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-all-v1.yaml -n bookinfo

# jason 사용자만 reviews:v2로 설정
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-reviews-test-v2.yaml -n bookinfo
```

### 7초 딜레이 주입

jason 사용자에게만 7초 딜레이가 발생하도록 설정합니다:

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-ratings-test-delay.yaml -n bookinfo
```

:::tip 실습 과제
7초 딜레이가 아닌 2초 딜레이를 주면 어떻게 되는지 확인해보세요.

힌트: [productpage 소스코드](https://github.com/istio/istio/blob/ea97d32cf46200d20378647d521001530f005bc8/samples/bookinfo/src/productpage/productpage.py#L400)를 참고하세요.
:::

### 리소스 정리

```bash
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-ratings-test-delay.yaml -n bookinfo
```

## HTTP Abort Fault 주입

ratings 서비스에 오류가 발생했다는 상황을 만들어 복원력을 확인합니다.

### 실습 목표

1. `http://$GATEWAY_URL_EXTERNAL/productpage`에 접속하여 새로고침할 때 v1으로 고정되는지 확인
2. jason 사용자에게 적용되는 규칙이 정상적으로 적용되는지 확인
3. 세 번째 규칙이 jason에게만 발생하고 로그인되지 않은 사용자에게는 정상적으로 v1으로 연결되는지 확인

### 설정

```bash
# 모든 요청을 v1으로
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-all-v1.yaml -n bookinfo

# jason 사용자만 v2로, 나머지는 v1으로
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-reviews-test-v2.yaml -n bookinfo

# v1에 500 에러 발생시키고 jason 사용자만 v1으로
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-ratings-test-abort.yaml -n bookinfo
```

### 트래픽 생성 및 Kiali에서 확인

다음 코드로 서비스 요청을 하는 동안 Kiali에서 실패 요청이 트래킹되는지 확인합니다:

```bash
# 100번 요청
for i in $(seq 1 100); do curl -o /dev/null -s -w "Request: ${i}, Response: %{http_code}\n" "http://$GATEWAY_URL_EXTERNAL/productpage"; done

# 무한 요청
let i=0; while :; do let i++; curl -o /dev/null -s -w "Request: ${i}, Response: %{http_code}\n" "http://$GATEWAY_URL_EXTERNAL/productpage"; done

# watch 사용
watch -n 1 curl -o /dev/null -s -w %{http_code} $GATEWAY_URL_EXTERNAL/productpage
```

### 리소스 정리

```bash
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-ratings-test-abort.yaml -n bookinfo
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-reviews-test-v2.yaml -n bookinfo
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-all-v1.yaml -n bookinfo
```

## 참고 자료

- [Istio Fault Injection 공식 문서](https://istio.io/latest/docs/tasks/traffic-management/fault-injection/)
