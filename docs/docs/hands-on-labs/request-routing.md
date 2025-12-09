# Request Routing

Request Routing을 통해 특정 버전의 서비스로 트래픽을 라우팅하는 방법을 실습합니다.

## 실습 목표

`http://$GATEWAY_URL_EXTERNAL/productpage`에 접속하여:
1. v1 적용 후 새로고침하여 v1으로 고정되는지 확인
2. 사용자 계정(jason/jason)으로 로그인 후 v1으로 유지되는지 확인
3. v2 적용 후 새로고침, 로그아웃 후 예상과 같이 동작하는지 확인
4. (선택) Kiali에서 요청이 v1으로만 가는지 확인

## 모든 요청을 reviews:v1으로 라우팅

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-all-v1.yaml -n bookinfo
```

<details>
<summary>virtual-service-all-v1.yaml 내용 보기</summary>

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: productpage
spec:
  hosts:
  - productpage
  http:
  - route:
    - destination:
        host: productpage
        subset: v1
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: reviews
spec:
  hosts:
  - reviews
  http:
  - route:
    - destination:
        host: reviews
        subset: v1
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: ratings
spec:
  hosts:
  - ratings
  http:
  - route:
    - destination:
        host: ratings
        subset: v1
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: details
spec:
  hosts:
  - details
  http:
  - route:
    - destination:
        host: details
        subset: v1
---
```

</details>

## jason 사용자만 reviews:v2로 라우팅

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-reviews-test-v2.yaml -n bookinfo
```

<details>
<summary>virtual-service-reviews-test-v2.yaml 내용 보기</summary>

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: reviews
spec:
  hosts:
    - reviews
  http:
  - match:
    - headers:
        end-user:
          exact: jason
    route:
    - destination:
        host: reviews
        subset: v2
  - route:
    - destination:
        host: reviews
        subset: v1
```

</details>

## 리소스 정리

```bash
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-reviews-test-v2.yaml -n bookinfo
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-all-v1.yaml -n bookinfo
```

## 참고 자료

- [Istio Bookinfo Networking 샘플](https://github.com/istio/istio/tree/master/samples/bookinfo/networking)
