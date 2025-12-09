# Bookinfo 샘플 애플리케이션 배포

## Istio 환경 구성

### AKS Preview 및 Service Mesh 활성화

```bash
# aks-preview 확장 설치
az extension add --name aks-preview
az extension update --name aks-preview

# AzureServiceMeshPreview 기능 등록
az feature register --namespace "Microsoft.ContainerService" --name "AzureServiceMeshPreview"

# 등록 상태 확인
az feature show --namespace "Microsoft.ContainerService" --name "AzureServiceMeshPreview"

# 프로바이더 등록 (권한 오류가 발생하는 경우 권한 있는 사용자가 실행 필요)
az provider register --namespace Microsoft.ContainerService
```

### 기존 클러스터에 Istio Service Mesh 활성화

```bash
# Service Mesh 활성화 [약 3-5분 소요]
az aks mesh enable --resource-group $RESOURCE_GROUP --name $CLUSTER

# 설정 확인 - "Istio" 출력 확인
az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER --query 'serviceMeshProfile.mode'

# aks-istio-system 네임스페이스의 파드 확인
kubectl get pods -n aks-istio-system
```

### 리소스 사용 확인

Envoy proxy 사용 전 리소스 현황:

```bash
kubectl top node --use-protocol-buffers
```

### Sidecar 주입 활성화

```bash
# bookinfo 네임스페이스 생성 및 레이블 설정
kubectl create ns bookinfo
kubectl label namespace bookinfo istio.io/rev=asm-1-18
```

Envoy proxy 사용 설정 후 리소스 사용률 확인 (20~30% 정도 증가 예상):

```bash
kubectl top node --use-protocol-buffers
```

### istioctl 설치

```bash
# 버전 확인
ISTIO_VERSION="$(kubectl get deploy istiod-asm-1-18 -n aks-istio-system -o yaml | grep image: | egrep -o '[0-9]+\.[0-9]+\.[0-9]+')"

# 설정된 버전 확인
echo $ISTIO_VERSION

# CLI 다운로드 및 설치
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION TARGET_ARCH=x86_64 sh -
sudo cp "istio-${ISTIO_VERSION}/bin/istioctl" /usr/local/bin
rm -rf "./istio-${ISTIO_VERSION}/"

# istio 버전 확인
istioctl -i aks-istio-system version
```

출력 예시:
```
client version: 1.18.7
control plane version: 1.18-dev
data plane version: none
```

:::note
data plane이 none으로 보여지는 이유는 아직 배포된 ingress/egress traffic, envoy proxy가 없기 때문입니다.
:::

### 외부 Ingress Gateway 활성화

```bash
# 외부 Ingress Gateway 활성화 [약 3-4분 소요]
az aks mesh enable-ingress-gateway \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --ingress-gateway-type external

# Public IP 및 포트 확인
kubectl get svc aks-istio-ingressgateway-external -n aks-istio-ingress

# istiod 버전 확인
kubectl get deploy -n aks-istio-system
```

### Istiod Dashboard (선택 사항)

```bash
ISTIOD_NAME=$(kubectl get deploy -n aks-istio-system | awk 'NR>1 {print $1}')

# istiod dashboard 실행
istioctl dashboard controlz deployment/$ISTIOD_NAME -n aks-istio-system
```

## 애플리케이션 배포

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/platform/kube/bookinfo.yaml -n bookinfo
```

## 서비스 생성 확인

```bash
kubectl get services -n bookinfo
```

## 파드 확인

```bash
kubectl get pods -n bookinfo
```

## DestinationRule 설정

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/bookinfo/networking/destination-rule-all.yaml -n bookinfo

# destinationrule 확인
kubectl get destinationrules -n bookinfo
```

## 내부 접속 테스트

```bash
kubectl exec "$(kubectl get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}' -n bookinfo)" -n bookinfo -c ratings -- curl -sS productpage:9080/productpage | grep -o "<title>.*</title>"
```

출력 결과:
```
<title>Simple Bookstore App</title>
```

## 외부 Ingress Gateway 설정

외부에서 접속할 수 있도록 external ingress gateway를 적용합니다:

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

## Gateway 및 VirtualService 확인

```bash
kubectl get gateway -n bookinfo
kubectl get virtualservices -n bookinfo
```

## 외부 접속 URL 확인

```bash
export INGRESS_HOST_EXTERNAL=$(kubectl -n aks-istio-ingress get service aks-istio-ingressgateway-external -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT_EXTERNAL=$(kubectl -n aks-istio-ingress get service aks-istio-ingressgateway-external -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export GATEWAY_URL_EXTERNAL=$INGRESS_HOST_EXTERNAL:$INGRESS_PORT_EXTERNAL

# URL 확인
echo "http://$GATEWAY_URL_EXTERNAL/productpage"
```

## 외부 접속 테스트

```bash
curl -s "http://${GATEWAY_URL_EXTERNAL}/productpage" | grep -o "<title>.*</title>"
```

출력 결과:
```
<title>Simple Bookstore App</title>
```

웹 브라우저에서 `http://$GATEWAY_URL_EXTERNAL/productpage`로 접속하면 Bookinfo 애플리케이션을 확인할 수 있습니다.
