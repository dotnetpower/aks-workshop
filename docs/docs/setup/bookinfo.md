# Bookinfo 샘플 애플리케이션 배포

이 문서에서는 AKS 클러스터에 Istio 서비스 메시 추가 기능을 설치하고 Bookinfo 샘플 애플리케이션을 배포하는 방법을 설명합니다.

## 사전 요구 사항

- AKS 클러스터가 생성되어 있어야 합니다 ([클러스터 구성](./cluster-setup.md) 참조)
- Azure CLI 버전 2.57.0 이상
- kubectl CLI 도구
- AKS 클러스터 버전 1.23 이상

## Istio 환경 구성

### 1. aks-preview 확장 설치

```bash
# aks-preview 확장 설치 및 업데이트
az extension add --name aks-preview
az extension update --name aks-preview
```

### 2. 사용 가능한 Istio 수정 버전 확인

```bash
# 지역별 사용 가능한 Istio 수정 버전 확인
az aks mesh get-revisions --location $LOCATION -o table
```

출력 예시:
```
MeshRevision    Upgrades           CompatibleWith
--------------  -----------------  ----------------
asm-1-24        -                  1.29, 1.30, 1.31
asm-1-23        asm-1-24           1.28, 1.29, 1.30
asm-1-22        asm-1-23, asm-1-24 1.27, 1.28, 1.29
```

:::info
수정 버전(Revision)은 Istio의 특정 버전을 나타냅니다. AKS는 여러 Istio 버전을 지원하며, 클러스터의 Kubernetes 버전과 호환되는 수정 버전을 선택할 수 있습니다.
:::

### 3. 기존 Istio 리소스 정리 (필요한 경우)

기존에 자체 관리형 Istio를 설치한 경우, CRD 및 관련 리소스를 정리합니다:

```bash
# 기존 Istio CRD 삭제
kubectl delete crd $(kubectl get crd -A | grep "istio.io" | awk '{print $1}')

# Istio 관련 ClusterRole, Webhook 등 정리
kubectl delete clusterroles,mutatingwebhookconfigurations,validatingwebhookconfigurations -l app.kubernetes.io/part-of=istio
```

:::warning
이 단계는 기존에 자체 관리형 Istio가 설치되어 있는 경우에만 실행하세요.
:::

### 4. Istio Service Mesh 활성화

기존 클러스터에 Istio 추가 기능을 활성화합니다:

```bash
# Service Mesh 활성화 [약 3-5분 소요]
az aks mesh enable --resource-group $RESOURCE_GROUP --name $CLUSTER

# 특정 수정 버전을 지정하려면:
# az aks mesh enable --resource-group $RESOURCE_GROUP --name $CLUSTER --revision asm-1-24
```

:::tip
새 클러스터를 생성하면서 Istio를 함께 설치하려면:
```bash
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --enable-asm \
  --generate-ssh-keys
```
:::

### 5. 설치 확인

```bash
# Istio가 활성화되었는지 확인 - "Istio" 출력 확인
az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER --query 'serviceMeshProfile.mode'

# 설치된 Istio 수정 버전 확인
az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER --query 'serviceMeshProfile.istio.revisions'

# aks-istio-system 네임스페이스의 파드 확인
kubectl get pods -n aks-istio-system
```

출력 예시:
```
NAME                               READY   STATUS    RESTARTS   AGE
istiod-asm-1-24-74f7f7c46c-xfdtl   1/1     Running   0          2m
istiod-asm-1-24-74f7f7c46c-4nt2v   1/1     Running   0          2m
```

모든 `istiod` Pod의 상태가 `Running`이어야 합니다.

### 6. Sidecar 주입 활성화

Istio는 사이드카 패턴을 사용하여 각 Pod에 Envoy 프록시를 주입합니다. 네임스페이스에 레이블을 추가하여 자동 사이드카 주입을 활성화합니다:

```bash
# bookinfo 네임스페이스 생성
kubectl create ns bookinfo

# 설치된 수정 버전 확인 (위에서 확인한 버전 사용)
ISTIO_REVISION=$(az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER --query 'serviceMeshProfile.istio.revisions[0]' -o tsv)
echo $ISTIO_REVISION

# 네임스페이스에 레이블 설정 (예: asm-1-24)
kubectl label namespace bookinfo istio.io/rev=$ISTIO_REVISION
```

:::important
- 반드시 `istio.io/rev=asm-X-Y` 형식의 명시적 수정 버전을 사용해야 합니다
- 기본 `istio-injection=enabled` 레이블은 AKS Istio 추가 기능에서 작동하지 않습니다
:::

### 7. istioctl CLI 설치

```bash
# 설치된 Istio 버전 확인
ISTIO_VERSION=$(kubectl get deploy -n aks-istio-system -o yaml | grep 'image:' | head -1 | sed -E 's/.*:(.*)/\1/' | cut -d'-' -f1)
echo "Istio Version: $ISTIO_VERSION"

# istioctl 다운로드 및 설치
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION TARGET_ARCH=x86_64 sh -
sudo cp "istio-${ISTIO_VERSION}/bin/istioctl" /usr/local/bin/
chmod +x /usr/local/bin/istioctl
rm -rf "./istio-${ISTIO_VERSION}/"

# 버전 확인
istioctl version -i aks-istio-system
```

출력 예시:
```
client version: 1.24.0
control plane version: 1.24.0
data plane version: none
```

:::note
`data plane version: none`이 표시되는 이유는 아직 사이드카가 주입된 Pod가 배포되지 않았기 때문입니다.
:::

### 8. 외부 Ingress Gateway 활성화

외부에서 Istio 메시 내부의 서비스에 접근하려면 Ingress Gateway를 활성화해야 합니다:

```bash
# 외부 Ingress Gateway 활성화 [약 3-4분 소요]
az aks mesh enable-ingress-gateway \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --ingress-gateway-type external

# Gateway 서비스 확인
kubectl get svc aks-istio-ingressgateway-external -n aks-istio-ingress

# External IP 확인 (EXTERNAL-IP가 할당될 때까지 대기)
kubectl get svc aks-istio-ingressgateway-external -n aks-istio-ingress -w
```

출력 예시:
```
NAME                                TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)
aks-istio-ingressgateway-external   LoadBalancer   10.0.123.45    20.200.100.50    15021:30123/TCP,80:31380/TCP,443:31390/TCP
```

### 9. Istiod Dashboard (선택 사항)

```bash
ISTIOD_NAME=$(kubectl get deploy -n aks-istio-system | awk 'NR>1 {print $1}')

# istiod dashboard 실행 (로컬에서 포트 포워딩)
istioctl dashboard controlz deployment/$ISTIOD_NAME -n aks-istio-system
```

브라우저에서 `http://localhost:9876`로 접속하여 Istiod 컨트롤 플레인 설정을 확인할 수 있습니다.

---

## Bookinfo 샘플 애플리케이션 배포

Bookinfo는 마이크로서비스 아키텍처를 보여주는 Istio의 공식 샘플 애플리케이션입니다.

### 애플리케이션 구조

- **productpage**: 제품 페이지 (Python)
- **details**: 제품 상세 정보 (Ruby)
- **reviews**: 제품 리뷰 (Java)
  - v1: 별점 없음
  - v2: 검은색 별점 (ratings 서비스 호출)
  - v3: 빨간색 별점 (ratings 서비스 호출)
- **ratings**: 별점 정보 (Node.js)

### 1. 애플리케이션 배포

```bash
# Bookinfo 애플리케이션 배포
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/bookinfo/platform/kube/bookinfo.yaml -n bookinfo
```

:::tip
아웃바운드 인터넷 접근을 위해 HTTP 프록시를 사용하는 클러스터의 경우, ServiceEntry를 설정해야 할 수 있습니다.
:::

### 2. 배포 확인

```bash
# 서비스 확인
kubectl get services -n bookinfo
```

출력 예시:
```
NAME          TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
details       ClusterIP   10.0.180.193   <none>        9080/TCP   87s
kubernetes    ClusterIP   10.0.0.1       <none>        443/TCP    15m
productpage   ClusterIP   10.0.112.238   <none>        9080/TCP   86s
ratings       ClusterIP   10.0.15.201    <none>        9080/TCP   86s
reviews       ClusterIP   10.0.73.95     <none>        9080/TCP   86s
```

```bash
# Pod 확인
kubectl get pods -n bookinfo
```

출력 예시:
```
NAME                              READY   STATUS    RESTARTS   AGE
details-v1-558b8b4b76-2llld       2/2     Running   0          2m41s
productpage-v1-6987489c74-lpkgl   2/2     Running   0          2m40s
ratings-v1-7dc98c7588-vzftc       2/2     Running   0          2m41s
reviews-v1-7f99cc4496-gdxfn       2/2     Running   0          2m41s
reviews-v2-7d79d5bd5d-8zzqd       2/2     Running   0          2m41s
reviews-v3-7dbcdcbc56-m8dph       2/2     Running   0          2m41s
```

:::important
모든 Pod의 `READY` 열이 `2/2`인지 확인하세요. 첫 번째 컨테이너는 애플리케이션이고, 두 번째 컨테이너(`istio-proxy`)는 Istio가 자동으로 주입한 Envoy 사이드카입니다.
:::

### 3. DestinationRule 설정

DestinationRule은 서비스의 하위 집합(subset)을 정의합니다:

```bash
# DestinationRule 적용
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/bookinfo/networking/destination-rule-all.yaml -n bookinfo

# 확인
kubectl get destinationrules -n bookinfo
```

### 4. 내부 접속 테스트

클러스터 내부에서 애플리케이션이 정상 동작하는지 확인합니다:

```bash
kubectl exec "$(kubectl get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}' -n bookinfo)" \
  -n bookinfo -c ratings -- \
  curl -sS productpage:9080/productpage | grep -o "<title>.*</title>"
```

출력 결과:
```
<title>Simple Bookstore App</title>
```

---

## 외부 접근 설정

### 1. Ingress Gateway 구성

외부에서 접속할 수 있도록 Gateway와 VirtualService를 생성합니다:

```bash
kubectl apply -n bookinfo -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: bookinfo-gateway-external
spec:
  selector:
    istio: aks-istio-ingressgateway-external
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: bookinfo-vs-external
spec:
  hosts:
  - "*"
  gateways:
  - bookinfo-gateway-external
  http:
  - match:
    - uri:
        exact: /productpage
    - uri:
        prefix: /static
    - uri:
        exact: /login
    - uri:
        exact: /logout
    - uri:
        prefix: /api/v1/products
    route:
    - destination:
        host: productpage
        port:
          number: 9080
EOF
```

### 2. Gateway 및 VirtualService 확인

```bash
# Gateway 확인
kubectl get gateway -n bookinfo

# VirtualService 확인
kubectl get virtualservices -n bookinfo
```

### 3. 외부 접속 URL 설정

```bash
# Ingress Gateway의 External IP 가져오기
export INGRESS_HOST_EXTERNAL=$(kubectl -n aks-istio-ingress get service aks-istio-ingressgateway-external -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Ingress Gateway의 포트 가져오기
export INGRESS_PORT_EXTERNAL=$(kubectl -n aks-istio-ingress get service aks-istio-ingressgateway-external -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')

# 전체 URL 구성
export GATEWAY_URL_EXTERNAL=$INGRESS_HOST_EXTERNAL:$INGRESS_PORT_EXTERNAL

# URL 출력
echo "Bookinfo URL: http://$GATEWAY_URL_EXTERNAL/productpage"
```

### 4. 외부 접속 테스트

터미널에서 curl로 테스트:

```bash
curl -s "http://${GATEWAY_URL_EXTERNAL}/productpage" | grep -o "<title>.*</title>"
```

출력 결과:
```
<title>Simple Bookstore App</title>
```

웹 브라우저에서 다음 URL로 접속:
```
http://$GATEWAY_URL_EXTERNAL/productpage
```

애플리케이션이 정상적으로 로드되고, 페이지를 새로고침할 때마다 다른 버전의 리뷰(별점 없음, 검은 별, 빨간 별)가 무작위로 표시되는 것을 확인할 수 있습니다.

---

## 다음 단계

축하합니다! Istio 서비스 메시와 Bookinfo 애플리케이션이 성공적으로 배포되었습니다.

이제 다음 실습으로 진행할 수 있습니다:

1. **[Request Routing](../istio/request-routing.md)**: 특정 버전으로 트래픽 라우팅
2. **[Traffic Shifting](../istio/traffic-shifting.md)**: 카나리 배포를 위한 가중치 기반 라우팅
3. **[Fault Injection](../istio/fault-injection.md)**: 장애 주입 테스트
4. **[Circuit Breaking](../istio/circuit-breaking.md)**: 회로 차단기 패턴
5. **[Authorization](../istio/authorization.md)**: JWT 기반 인증 및 권한 부여

## 참고 자료

- [Azure AKS Istio 추가 기능 배포](https://learn.microsoft.com/ko-kr/azure/aks/istio-deploy-addon)
- [Istio Bookinfo 애플리케이션](https://istio.io/latest/docs/examples/bookinfo/)
- [Istio Ingress Gateway](https://learn.microsoft.com/ko-kr/azure/aks/istio-deploy-ingress)
