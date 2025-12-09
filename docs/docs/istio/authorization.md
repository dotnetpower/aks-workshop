# Authorization - HTTP Traffic

HTTP 트래픽에 대해 ALLOW 액션 정책 설정으로 접속 허용/거부를 적용합니다.

참고: [Istio HTTP Authorization 공식 문서](https://istio.io/latest/docs/tasks/security/authorization/authz-http/)

## 모든 요청 차단

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-nothing
  namespace: bookinfo
spec:
  {}
EOF
```

`http://$GATEWAY_URL_EXTERNAL/productpage` 페이지를 새로고침하면 `RBAC: access denied` 오류가 발생합니다.

## productpage만 허용

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: "productpage-viewer"
  namespace: bookinfo
spec:
  selector:
    matchLabels:
      app: productpage
  action: ALLOW
  rules:
  - to:
    - operation:
        methods: ["GET"]
EOF
```

이제 productpage는 접근 가능하지만, details, reviews, ratings는 여전히 차단됩니다.

## details 서비스 허용

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: "details-viewer"
  namespace: bookinfo
spec:
  selector:
    matchLabels:
      app: details
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/bookinfo/sa/bookinfo-productpage"]
    to:
    - operation:
        methods: ["GET"]
EOF
```

details 서비스는 `bookinfo-productpage` 서비스 계정으로부터의 GET 요청만 허용합니다.

## reviews 서비스 허용

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: "reviews-viewer"
  namespace: bookinfo
spec:
  selector:
    matchLabels:
      app: reviews
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/bookinfo/sa/bookinfo-productpage"]
    to:
    - operation:
        methods: ["GET"]
EOF
```

## ratings 서비스 허용

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: "ratings-viewer"
  namespace: bookinfo
spec:
  selector:
    matchLabels:
      app: ratings
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/bookinfo/sa/bookinfo-reviews"]
    to:
    - operation:
        methods: ["GET"]
EOF
```

ratings 서비스는 `bookinfo-reviews` 서비스 계정으로부터의 GET 요청만 허용합니다.

## 최종 확인

모든 정책을 적용한 후 `http://$GATEWAY_URL_EXTERNAL/productpage`에 접속하면 정상적으로 모든 서비스가 작동합니다.

## Authorization Policy 구조 이해

AuthorizationPolicy는 다음과 같은 구조로 구성됩니다:

- **selector**: 정책을 적용할 워크로드 선택
- **action**: ALLOW, DENY, AUDIT, CUSTOM 중 선택
- **rules**: 
  - **from**: 요청의 출처 (서비스 계정, 네임스페이스 등)
  - **to**: 요청의 대상 (operation, path 등)
  - **when**: 추가 조건 (헤더, IP 주소 등)

## 정리

```bash
kubectl delete authorizationpolicy allow-nothing -n bookinfo
kubectl delete authorizationpolicy productpage-viewer -n bookinfo
kubectl delete authorizationpolicy details-viewer -n bookinfo
kubectl delete authorizationpolicy reviews-viewer -n bookinfo
kubectl delete authorizationpolicy ratings-viewer -n bookinfo
```

## 추가 실습

:::tip 실습 과제
1. 특정 IP 주소만 허용하는 정책을 만들어보세요
2. DENY 액션을 사용하여 특정 경로를 차단해보세요
3. 헤더 기반 authorization을 구성해보세요
:::
