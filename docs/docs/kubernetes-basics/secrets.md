# Secret

Secret은 Kubernetes에서 비밀번호, OAuth 토큰, SSH 키와 같은 민감한 정보를 안전하게 저장하고 관리하는 리소스입니다.

## Secret이란?

Secret을 사용하면 민감한 정보를 안전하게 관리할 수 있습니다:

* 민감한 데이터를 이미지에서 분리
* Base64 인코딩으로 데이터 저장
* RBAC를 통한 접근 제어
* etcd에 암호화 저장 가능 (클러스터 설정에 따라)

:::warning 중요
Secret의 데이터는 Base64로 인코딩되어 있지만 **암호화되지 않습니다**. 클러스터 수준의 암호화와 RBAC를 통해 보안을 강화해야 합니다.
:::

## ConfigMap vs Secret

| 항목 | ConfigMap | Secret |
|------|-----------|--------|
| 용도 | 일반 설정 데이터 | 민감한 데이터 |
| 저장 방식 | 평문 | Base64 인코딩 |
| 크기 제한 | 1MB | 1MB |
| 암호화 | 없음 | etcd 암호화 가능 |

## Base64 인코딩/디코딩

Secret을 생성하기 전에 데이터를 Base64로 인코딩해야 합니다:

```bash
# 인코딩
echo -n "mypassword" | base64
# 출력: bXlwYXNzd29yZA==

echo -n "Don't look, I'm a secret" | base64
# 출력: RG9uJ3QgbG9vaywgSSdtIGEgc2VjcmV0

# 디코딩
echo "bXlwYXNzd29yZA==" | base64 -d
# 출력: mypassword

echo "RG9uJ3QgbG9vaywgSSdtIGEgc2VjcmV0" | base64 -d
# 출력: Don't look, I'm a secret
```

## Secret 생성 방법

### 1. Literal 값으로 생성

```bash
kubectl create secret generic simple-secret \
  --from-literal=username=admin \
  --from-literal=password=mypassword
```

또는 YAML로 (Base64 인코딩 필요):

```yaml title="simple-secret.yaml"
apiVersion: v1
kind: Secret
metadata:
  name: simple-secret
  labels:
    scope: demo
data:
  cert: RG9uJ3QgbG9vaywgSSdtIGEgc2VjcmV0
  key: dmFsdWU=
type: Opaque
```

```bash
kubectl apply -f simple-secret.yaml
```

### 2. 여러 키-값 쌍

```yaml title="simple-secret2.yaml"
apiVersion: v1
kind: Secret
metadata:
  name: simple-secret2
  labels:
    scope: demo
data:
  dbpassword: RG9uJ3QgbG9vaywgSSdtIGEgc2VjcmV0
type: Opaque
```

```bash
kubectl apply -f simple-secret2.yaml
```

### 3. 파일로 생성

```yaml title="file-secret.yaml"
apiVersion: v1
kind: Secret
metadata:
  name: file-secret
  labels:
    scope: demo
data:
  somevalue: VGhpcyBpcyBhIHNlY3JldCB2YWx1ZSBpbiBhIGZpbGU=
  anothervalue: VGhpcyBpcyBzb21lIG90aGVyIHN0cmluZyB0aGF0IEkgd2FudCB0byBtYWtlIGludG8gYSBzZWNyZXR0
type: Opaque
```

```bash
kubectl apply -f file-secret.yaml
```

### 4. 파일에서 직접 생성

```bash
# 파일 생성
cat > db-credentials.txt <<EOF
username=admin
password=secretpass123
EOF

# Secret 생성
kubectl create secret generic db-credentials \
  --from-file=db-credentials.txt

# 여러 파일에서
kubectl create secret generic app-secrets \
  --from-file=username.txt \
  --from-file=password.txt
```

## Secret 확인

```bash
# 모든 Secret 목록
kubectl get secrets

# 특정 Secret 상세 정보
kubectl describe secret simple-secret

# YAML 형식으로 확인 (Base64 인코딩된 값)
kubectl get secret simple-secret -o yaml

# 특정 키의 값 디코딩
kubectl get secret simple-secret -o jsonpath='{.data.cert}' | base64 -d
kubectl get secret simple-secret -o jsonpath='{.data.key}' | base64 -d
```

## Pod에서 Secret 사용

### 1. 환경 변수로 주입

```yaml title="pod-secret-env.yaml"
apiVersion: v1
kind: Pod
metadata:
  name: secret-env-pod
spec:
  containers:
    - name: app
      image: nginx:1.27
      env:
        # 개별 키를 환경 변수로
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: simple-secret2
              key: dbpassword
        - name: CERT_DATA
          valueFrom:
            secretKeyRef:
              name: simple-secret
              key: cert
```

### 2. 모든 Secret을 환경 변수로

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secret-envfrom-pod
spec:
  containers:
    - name: app
      image: nginx:1.27
      envFrom:
        - secretRef:
            name: simple-secret
```

### 3. 볼륨으로 마운트

```yaml title="pod-secret-volume.yaml"
apiVersion: v1
kind: Pod
metadata:
  name: secret-volume-pod
spec:
  containers:
    - name: app
      image: nginx:1.27
      volumeMounts:
        - name: secret-volume
          mountPath: /secret-data
          readOnly: true
  volumes:
    - name: secret-volume
      secret:
        secretName: file-secret
```

마운트된 경로에서 각 키는 별도의 파일로 생성됩니다:
```
/secret-data/somevalue
/secret-data/anothervalue
```

### 4. 완전한 Deployment 예제

```yaml title="workload-2-dep.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-2-dep
  labels:
    scope: demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: workload-2
  template:
    metadata:
      labels:
        app: workload-2
        color: yellow
    spec:
      nodeSelector:
        kubernetes.io/os: linux
      containers:
        - name: workload
          image: nginx:1.27
          ports:
            - containerPort: 80
          # 모든 Secret 키를 환경 변수로
          envFrom:
            - secretRef:
                name: simple-secret
          # 개별 환경 변수
          env:
            - name: MD_SERVICE_MAP_FILE
              value: /config/service-mappings.json
            - name: MD_ACKNOWLEDGE_HEARTBEAT
              value: "false"
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: simple-secret2
                  key: dbpassword
          # 볼륨 마운트
          volumeMounts:
            - name: secret-volume
              mountPath: /secret-data
      volumes:
        - name: secret-volume
          secret:
            secretName: file-secret
```

## 실습: Secret 생성 및 사용

### 1. Secret 생성

```bash
# YAML 파일 생성
kubectl apply -f simple-secret.yaml
kubectl apply -f simple-secret2.yaml
kubectl apply -f file-secret.yaml

# Secret 확인
kubectl get secrets -l scope=demo
kubectl describe secret simple-secret
```

### 2. Deployment 배포

```bash
kubectl apply -f workload-2-dep.yaml

# Pod 상태 확인
kubectl get pods -l app=workload-2
```

### 3. Pod에서 Secret 확인

```bash
# Pod 이름 가져오기
POD_NAME=$(kubectl get pods -l app=workload-2 -o jsonpath='{.items[0].metadata.name}')

# Pod에 접속
kubectl exec -it $POD_NAME -- /bin/bash

# 환경 변수로 주입된 Secret 확인
echo $DB_PASSWORD
echo $cert
echo $key

# 모든 환경 변수 확인
env | grep -E "cert|key|DB_PASSWORD"

# 볼륨으로 마운트된 Secret 확인
ls -la /secret-data
cat /secret-data/somevalue
cat /secret-data/anothervalue

# 종료
exit
```

### 4. Secret 값 디코딩

```bash
# Base64로 인코딩된 값 확인
kubectl get secret simple-secret -o yaml

# 특정 키 디코딩
kubectl get secret simple-secret -o jsonpath='{.data.cert}' | base64 -d
echo ""  # 줄바꿈

kubectl get secret simple-secret2 -o jsonpath='{.data.dbpassword}' | base64 -d
echo ""

kubectl get secret file-secret -o jsonpath='{.data.somevalue}' | base64 -d
echo ""
```

## Secret 타입

Kubernetes는 여러 타입의 Secret을 지원합니다:

### 1. Opaque (기본값)

일반적인 키-값 데이터:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: opaque-secret
type: Opaque
data:
  api-key: YXBpLWtleS12YWx1ZQ==
```

### 2. kubernetes.io/dockerconfigjson

Docker 레지스트리 인증:

```bash
kubectl create secret docker-registry myregistrykey \
  --docker-server=myregistry.azurecr.io \
  --docker-username=myusername \
  --docker-password=mypassword \
  --docker-email=myemail@example.com
```

사용 예:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: private-pod
spec:
  containers:
    - name: app
      image: myregistry.azurecr.io/myapp:latest
  imagePullSecrets:
    - name: myregistrykey
```

### 3. kubernetes.io/tls

TLS 인증서:

```bash
kubectl create secret tls tls-secret \
  --cert=path/to/tls.cert \
  --key=path/to/tls.key
```

Ingress에서 사용:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tls-ingress
spec:
  tls:
    - hosts:
        - myapp.example.com
      secretName: tls-secret
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  number: 80
```

### 4. kubernetes.io/basic-auth

기본 인증:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: basic-auth
type: kubernetes.io/basic-auth
stringData:
  username: admin
  password: secretpassword
```

### 5. kubernetes.io/ssh-auth

SSH 인증:

```bash
kubectl create secret generic ssh-key-secret \
  --from-file=ssh-privatekey=/path/to/.ssh/id_rsa \
  --type=kubernetes.io/ssh-auth
```

## Secret 업데이트

### 1. Secret 수정

```bash
kubectl edit secret simple-secret
```

또는:

```bash
# 새로운 값을 Base64로 인코딩
NEW_VALUE=$(echo -n "newpassword" | base64)

# Secret 업데이트
kubectl patch secret simple-secret \
  --type merge \
  -p "{\"data\":{\"key\":\"$NEW_VALUE\"}}"
```

### 2. Pod 재시작

:::warning 주의
환경 변수로 주입된 Secret은 Pod를 재시작해야 업데이트됩니다.
:::

```bash
kubectl rollout restart deployment workload-2-dep
```

### 3. 볼륨 마운트 자동 업데이트

볼륨으로 마운트된 Secret은 자동으로 업데이트됩니다 (최대 1-2분 소요).

## stringData 사용

Base64 인코딩 없이 Secret 생성:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: string-secret
type: Opaque
stringData:
  username: admin
  password: mypassword123
  config.yaml: |
    apiUrl: https://api.example.com
    timeout: 30
```

:::info 참고
`stringData`는 생성 시 자동으로 Base64로 인코딩되어 `data` 필드에 저장됩니다.
:::

## 보안 모범 사례

### 1. RBAC 설정

Secret 접근 제한:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-reader
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list"]
    resourceNames: ["simple-secret"]  # 특정 Secret만
```

### 2. etcd 암호화 활성화

AKS에서는 기본적으로 etcd 암호화가 활성화되어 있습니다.

### 3. 외부 비밀 관리 시스템 사용

- Azure Key Vault Provider for Secrets Store CSI Driver
- HashiCorp Vault
- AWS Secrets Manager

Azure Key Vault 통합 예:

```bash
# CSI Driver 설치 (AKS에 기본 포함)
az aks enable-addons \
  --addons azure-keyvault-secrets-provider \
  --name myAKSCluster \
  --resource-group myResourceGroup
```

### 4. Immutable Secret

변경되지 않아야 하는 Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: immutable-secret
type: Opaque
data:
  api-key: YXBpLWtleS12YWx1ZQ==
immutable: true
```

## 리소스 정리

```bash
kubectl delete deployment -l scope=demo
kubectl delete secret -l scope=demo
```

## 실습 과제

:::tip 실습 과제
1. 다양한 방법으로 Secret을 생성하고 확인하세요
2. 환경 변수와 볼륨 마운트 방식의 차이를 이해하세요
3. Base64 인코딩/디코딩을 직접 수행하세요
4. `stringData`를 사용하여 Secret을 생성하고 `data` 필드와 비교하세요
5. Secret을 업데이트하고 Pod에 반영되는 과정을 관찰하세요
6. Docker registry Secret을 생성하고 private 이미지를 pull하세요
7. TLS Secret을 생성하고 Ingress에서 사용하세요
:::

## 다음 단계

[Blue-Green Deployments](./blue-green-deployments)에서 무중단 배포 전략을 배웁니다.
