# Traffic Shifting

Traffic Shifting을 통해 여러 버전 간에 트래픽을 분산하는 방법을 실습합니다.

## 실습 목표

reviews 버전에 따라 트래픽을 지정하고, CI/CD 파이프라인 구성 시 카나리 배포 적용 방안을 고민합니다.

## v1과 v3에 각각 50%씩 트래픽 분배

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-reviews-50-v3.yaml -n bookinfo
```

<details>
<summary>virtual-service-reviews-50-v3.yaml 내용 보기</summary>

```yaml
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
      weight: 50
    - destination:
        host: reviews
        subset: v3
      weight: 50
```

</details>

## v2와 v3에 각각 50%씩 트래픽 분배

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-reviews-v2-v3.yaml -n bookinfo
```

## v3에 100% 트래픽 할당

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-reviews-v3.yaml -n bookinfo
```

<details>
<summary>virtual-service-reviews-v3.yaml 내용 보기</summary>

```yaml
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
        subset: v3
```

</details>

## 카나리 배포 시나리오

Traffic Shifting을 활용한 카나리 배포:

1. 초기: 모든 트래픽을 v1으로 (100%)
2. 1단계: v1 90% + v3 10%
3. 2단계: v1 50% + v3 50%
4. 최종: v3 100%

각 단계에서 모니터링 도구(Kiali, Grafana)를 통해 성능 및 에러율을 확인하고, 문제가 없으면 다음 단계로 진행합니다.

## 리소스 정리

```bash
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-reviews-v3.yaml -n bookinfo
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-reviews-v2-v3.yaml -n bookinfo
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/virtual-service-reviews-50-v3.yaml -n bookinfo
```
