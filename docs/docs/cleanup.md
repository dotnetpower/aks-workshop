# 리소스 정리

워크샵을 완료한 후 생성한 모든 리소스를 정리합니다.

## Istio Mesh 비활성화

```bash
az aks mesh disable --resource-group ${RESOURCE_GROUP} --name ${CLUSTER}
```

## Istio CRD 삭제

```bash
kubectl delete crd $(kubectl get crd -A | grep "istio.io" | awk '{print $1}')
```

## 리소스 그룹 전체 삭제

:::danger 주의
이 명령은 리소스 그룹과 그 안의 모든 리소스를 삭제합니다. 실행 전에 반드시 확인하세요.
:::

```bash
az group delete --name ${RESOURCE_GROUP} --yes --no-wait
```

## 선택적 리소스 정리

전체 리소스 그룹을 삭제하지 않고 개별적으로 정리하려면:

### Bookinfo 애플리케이션 삭제

```bash
kubectl delete namespace bookinfo
```

### 모니터링 도구 삭제

```bash
# Kiali
helm uninstall kiali-operator -n aks-istio-system

# Prometheus, Grafana, Jaeger
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/addons/prometheus.yaml -n aks-istio-system
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/addons/grafana.yaml -n aks-istio-system
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/addons/jaeger.yaml -n aks-istio-system
```

### ClusterInfo 삭제 (설치한 경우)

```bash
helm uninstall clusterinfo -n clusterinfo
kubectl delete namespace clusterinfo
```

## 환경 변수 정리

```bash
unset CLUSTER
unset RESOURCE_GROUP
unset LOCATION
unset K8S_VERSION
unset INGRESS_HOST_EXTERNAL
unset INGRESS_PORT_EXTERNAL
unset GATEWAY_URL_EXTERNAL
unset ISTIO_VERSION
unset ISTIOD_NAME
unset FORTIO_POD
unset JAEGER_POD
```

## 로컬 도구 정리

### istioctl 제거

```bash
sudo rm -f /usr/local/bin/istioctl
```

## 확인

모든 리소스가 정리되었는지 확인:

```bash
# 리소스 그룹 확인
az group list --output table | grep ${RESOURCE_GROUP}

# 클러스터 확인
az aks list --output table
```

## 비용 절감 팁

리소스를 즉시 삭제하지 않고 유지하려는 경우:

1. **클러스터 중지**: 사용하지 않을 때 클러스터를 중지하여 비용 절감
   ```bash
   az aks stop --name ${CLUSTER} --resource-group ${RESOURCE_GROUP}
   ```

2. **클러스터 시작**: 필요할 때 다시 시작
   ```bash
   az aks start --name ${CLUSTER} --resource-group ${RESOURCE_GROUP}
   ```

3. **노드 스케일 다운**: 노드 수를 줄여서 비용 절감
   ```bash
   az aks scale --name ${CLUSTER} --resource-group ${RESOURCE_GROUP} --node-count 1
   ```
