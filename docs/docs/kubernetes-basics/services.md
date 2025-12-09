# Service

Kubernetes Service는 Pod 집합에 대한 안정적인 네트워크 엔드포인트를 제공합니다.

## Service란?

Pod는 생성될 때마다 IP가 변경되므로 직접 접근하기 어렵습니다. Service는 다음과 같은 기능을 제공합니다:

* Pod 집합에 대한 안정적인 IP와 DNS 이름 제공
* 로드 밸런싱을 통한 트래픽 분산
* 서비스 디스커버리 지원

## Service 타입

### 1. ClusterIP (기본값)

클러스터 내부에서만 접근 가능한 IP를 할당합니다.

### 2. NodePort

각 노드의 특정 포트를 통해 외부에서 접근할 수 있습니다.

### 3. LoadBalancer

클라우드 제공자의 로드 밸런서를 프로비저닝합니다.

## 실습: Service 타입 변경

### 1. Deployment 생성

```yaml title="workload-dep.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-dep
spec:
  replicas: 3
  selector:
    matchLabels:
      app: webserver
  template:
    metadata:
      labels:
        app: webserver
    spec:
      containers:
        - name: nginx
          image: nginx:1.21
          ports:
            - containerPort: 80
```

```bash
kubectl apply -f workload-dep.yaml
```

### 2. ClusterIP Service 생성

```yaml title="workload-svc-clusterip.yaml"
apiVersion: v1
kind: Service
metadata:
  name: workload-svc
spec:
  type: ClusterIP
  selector:
    app: webserver
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
```

```bash
kubectl apply -f workload-svc-clusterip.yaml

# Service 확인
kubectl get svc workload-svc

# 출력 예시:
# NAME           TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
# workload-svc   ClusterIP   10.0.123.45    <none>        80/TCP    10s
```

ClusterIP는 클러스터 내부에서만 접근 가능합니다:

```bash
# 클러스터 내부에서 테스트
kubectl run test-pod --image=busybox -it --rm -- wget -qO- http://workload-svc
```

### 3. NodePort로 업그레이드

```yaml title="workload-svc-nodeport.yaml"
apiVersion: v1
kind: Service
metadata:
  name: workload-svc
spec:
  type: NodePort
  selector:
    app: webserver
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
      nodePort: 30080  # 30000-32767 범위 (생략 시 자동 할당)
```

```bash
kubectl apply -f workload-svc-nodeport.yaml

# Service 확인
kubectl get svc workload-svc

# 출력 예시:
# NAME           TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
# workload-svc   NodePort   10.0.123.45    <none>        80:30080/TCP   2m
```

이제 `<NODE-IP>:30080`으로 외부에서 접근할 수 있습니다:

```bash
# 노드 IP 확인
kubectl get nodes -o wide

# 접근 테스트
curl http://<NODE-IP>:30080
```

### 4. LoadBalancer로 업그레이드

```yaml title="workload-svc-loadbalancer.yaml"
apiVersion: v1
kind: Service
metadata:
  name: workload-svc
spec:
  type: LoadBalancer
  selector:
    app: webserver
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
```

```bash
kubectl apply -f workload-svc-loadbalancer.yaml

# Service 확인
kubectl get svc workload-svc -w
```

:::info 대기 시간
Azure에서 외부 IP가 할당되는 데 1-2분 정도 소요됩니다.
:::

```bash
# 출력 예시:
# NAME           TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)        AGE
# workload-svc   LoadBalancer   10.0.123.45    20.200.100.50    80:31234/TCP   3m
```

외부 IP로 접근 테스트:

```bash
# 웹 브라우저에서 접근
echo "http://$(kubectl get svc workload-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"

# 또는 curl로 테스트
EXTERNAL_IP=$(kubectl get svc workload-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$EXTERNAL_IP
```

## 로드 밸런싱 확인

### 1. Pod 식별을 위한 HTML 파일 생성

각 Pod를 구분할 수 있도록 Deployment를 수정합니다:

```yaml title="workload-dep-update.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-dep
spec:
  replicas: 3
  selector:
    matchLabels:
      app: webserver
  template:
    metadata:
      labels:
        app: webserver
    spec:
      containers:
        - name: nginx
          image: nginx:1.21
          ports:
            - containerPort: 80
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
          lifecycle:
            postStart:
              exec:
                command:
                  - /bin/sh
                  - -c
                  - echo "Pod: $POD_NAME, IP: $POD_IP" > /usr/share/nginx/html/index.html
```

```bash
kubectl apply -f workload-dep-update.yaml
```

### 2. 로드 밸런싱 테스트

```bash
# 여러 번 요청하여 다른 Pod로 분산되는지 확인
for i in {1..10}; do
  curl http://$EXTERNAL_IP
  echo ""
done
```

출력 예시:
```
Pod: workload-dep-abc123, IP: 10.244.1.5
Pod: workload-dep-def456, IP: 10.244.2.8
Pod: workload-dep-abc123, IP: 10.244.1.5
Pod: workload-dep-ghi789, IP: 10.244.3.2
...
```

## Service Selector

Service는 Label Selector를 사용하여 대상 Pod를 선택합니다:

```yaml
spec:
  selector:
    app: webserver  # 이 레이블을 가진 모든 Pod가 대상
```

Pod의 레이블 확인:

```bash
kubectl get pods --show-labels
```

## Endpoints 확인

Service가 실제로 연결된 Pod IP 목록을 확인합니다:

```bash
kubectl get endpoints workload-svc

# 상세 정보
kubectl describe endpoints workload-svc
```

## SessionAffinity

같은 클라이언트의 요청을 동일한 Pod로 라우팅합니다:

```yaml
spec:
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 10800  # 3시간
```

## Headless Service

ClusterIP를 할당하지 않고 Pod IP를 직접 반환합니다:

```yaml title="workload-svc-headless.yaml"
apiVersion: v1
kind: Service
metadata:
  name: workload-svc-headless
spec:
  clusterIP: None
  selector:
    app: webserver
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
```

```bash
kubectl apply -f workload-svc-headless.yaml

# DNS 조회 (모든 Pod IP 반환)
kubectl run test-pod --image=busybox -it --rm -- nslookup workload-svc-headless
```

## 리소스 정리

```bash
kubectl delete deployment workload-dep
kubectl delete service workload-svc
```

## 실습 과제

:::tip 실습 과제
1. ClusterIP, NodePort, LoadBalancer를 순서대로 적용하고 각 타입의 특징을 확인하세요
2. Service의 Endpoints를 확인하고 Pod와의 연결을 이해하세요
3. 로드 밸런싱이 어떻게 작동하는지 여러 번 요청하여 확인하세요
4. SessionAffinity를 설정하고 동작을 테스트하세요
5. Headless Service를 생성하고 DNS 조회 결과를 확인하세요
:::

## 다음 단계

[ConfigMap](./configmaps)에서 애플리케이션 설정을 관리하는 방법을 배웁니다.
