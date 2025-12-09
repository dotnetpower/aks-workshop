# ConfigMap

ConfigMap은 애플리케이션의 설정 데이터를 관리하는 Kubernetes 리소스입니다.

## ConfigMap이란?

ConfigMap을 사용하면 컨테이너 이미지와 설정을 분리할 수 있습니다:

* 환경별로 다른 설정 적용 가능
* 설정 변경 시 이미지 재빌드 불필요
* 중앙 집중식 설정 관리

## ConfigMap 생성 방법

### 1. Literal 값으로 생성

```bash
kubectl create configmap simple-configmap \
  --from-literal=app.name=MyApp \
  --from-literal=app.version=1.0.0 \
  --from-literal=app.env=development
```

또는 YAML로:

```yaml title="simple-configmap.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: simple-configmap
  labels:
    scope: demo
data:
  app.name: "MyApp"
  app.version: "1.0.0"
  app.env: "development"
```

```bash
kubectl apply -f simple-configmap.yaml
```

### 2. 파일에서 생성

```bash
# 설정 파일 생성
cat > app.properties <<EOF
database.host=localhost
database.port=5432
database.name=mydb
log.level=INFO
EOF

# ConfigMap 생성
kubectl create configmap file-configmap \
  --from-file=app.properties
```

또는 YAML로:

```yaml title="file-configmap.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: file-configmap
  labels:
    scope: demo
data:
  app.properties: |
    database.host=localhost
    database.port=5432
    database.name=mydb
    log.level=INFO
```

```bash
kubectl apply -f file-configmap.yaml
```

### 3. 여러 키-값 쌍

```yaml title="simple-configmap2.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: simple-configmap2
  labels:
    scope: demo
data:
  color: "blue"
  size: "large"
  cache.ttl: "3600"
  feature.enabled: "true"
```

```bash
kubectl apply -f simple-configmap2.yaml
```

## ConfigMap 확인

```bash
# 모든 ConfigMap 목록
kubectl get configmaps

# 특정 ConfigMap 상세 정보
kubectl describe configmap simple-configmap

# YAML 형식으로 확인
kubectl get configmap simple-configmap -o yaml
```

## Pod에서 ConfigMap 사용

### 1. 환경 변수로 주입

```yaml title="workload-dep-env.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-1-dep
  labels:
    scope: demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: workload-1
  template:
    metadata:
      labels:
        app: workload-1
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          env:
            # 개별 키를 환경 변수로
            - name: APP_NAME
              valueFrom:
                configMapKeyRef:
                  name: simple-configmap
                  key: app.name
            - name: APP_VERSION
              valueFrom:
                configMapKeyRef:
                  name: simple-configmap
                  key: app.version
            # 모든 키를 환경 변수로
          envFrom:
            - configMapRef:
                name: simple-configmap2
```

### 2. 볼륨으로 마운트

```yaml title="workload-dep-volume.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-1-dep
  labels:
    scope: demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: workload-1
  template:
    metadata:
      labels:
        app: workload-1
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          volumeMounts:
            # 파일로 마운트
            - name: config-volume
              mountPath: /etc/config
            # 특정 키만 특정 경로에 마운트
            - name: config-file
              mountPath: /app/config/app.properties
              subPath: app.properties
      volumes:
        # ConfigMap 전체를 볼륨으로
        - name: config-volume
          configMap:
            name: simple-configmap
        # 특정 키만 파일로
        - name: config-file
          configMap:
            name: file-configmap
```

### 3. 완전한 예제

```yaml title="workload-1-dep.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-1-dep
  labels:
    scope: demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: workload-1
  template:
    metadata:
      labels:
        app: workload-1
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          # 환경 변수로 주입
          env:
            - name: APP_NAME
              valueFrom:
                configMapKeyRef:
                  name: simple-configmap
                  key: app.name
            - name: APP_VERSION
              valueFrom:
                configMapKeyRef:
                  name: simple-configmap
                  key: app.version
          envFrom:
            - configMapRef:
                name: simple-configmap2
          # 볼륨으로 마운트
          volumeMounts:
            - name: config-volume
              mountPath: /etc/config
            - name: file-volume
              mountPath: /app/config
      volumes:
        - name: config-volume
          configMap:
            name: simple-configmap
        - name: file-volume
          configMap:
            name: file-configmap
```

```bash
kubectl apply -f simple-configmap.yaml \
              -f simple-configmap2.yaml \
              -f file-configmap.yaml \
              -f workload-1-dep.yaml
```

## ConfigMap 확인하기

Pod에 접속하여 ConfigMap이 올바르게 로드되었는지 확인:

```bash
# Pod 이름 가져오기
POD_NAME=$(kubectl get pods -l app=workload-1 -o jsonpath='{.items[0].metadata.name}')

# Pod에 접속
kubectl exec -it $POD_NAME -- /bin/bash

# 환경 변수 확인
env | grep -E "APP_|color|size|cache|feature"

# 마운트된 파일 확인
ls -la /etc/config
cat /etc/config/app.name
cat /etc/config/app.version

ls -la /app/config
cat /app/config/app.properties

# 종료
exit
```

## ConfigMap 업데이트

### 1. ConfigMap 수정

```bash
kubectl edit configmap simple-configmap
```

또는:

```bash
kubectl patch configmap simple-configmap \
  --type merge \
  -p '{"data":{"app.version":"2.0.0"}}'
```

### 2. Pod 재시작 (환경 변수의 경우)

:::warning 주의
환경 변수로 주입된 ConfigMap 값은 Pod를 재시작해야 업데이트됩니다.
:::

```bash
kubectl rollout restart deployment workload-1-dep
```

### 3. 자동 업데이트 (볼륨 마운트의 경우)

볼륨으로 마운트된 ConfigMap은 자동으로 업데이트됩니다 (최대 1-2분 소요):

```bash
# ConfigMap 업데이트
kubectl patch configmap file-configmap \
  --type merge \
  -p '{"data":{"app.properties":"database.host=prod-server\ndatabase.port=5432"}}'

# 약 1-2분 후 확인
kubectl exec -it $POD_NAME -- cat /app/config/app.properties
```

## Immutable ConfigMap

변경되지 않아야 하는 ConfigMap은 immutable로 설정:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: immutable-configmap
data:
  config.json: |
    {
      "version": "1.0.0",
      "production": true
    }
immutable: true
```

:::info 이점
- 실수로 인한 변경 방지
- kubelet의 watch 부하 감소
- 성능 향상
:::

## 리소스 정리

```bash
kubectl delete deployment -l scope=demo
kubectl delete configmap -l scope=demo
```

## 실습 과제

:::tip 실습 과제
1. Literal 값, 파일, 디렉터리로 ConfigMap을 생성하세요
2. 환경 변수와 볼륨 마운트 방식의 차이를 이해하세요
3. ConfigMap을 업데이트하고 Pod에 반영되는 과정을 관찰하세요
4. 환경 변수 방식과 볼륨 방식의 업데이트 동작 차이를 확인하세요
5. Immutable ConfigMap을 생성하고 수정을 시도하세요
:::

## 다음 단계

[Secret](./secrets)에서 민감한 정보를 안전하게 관리하는 방법을 배웁니다.
