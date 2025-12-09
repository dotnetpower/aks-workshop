# 볼륨과 스토리지

Kubernetes에서 컨테이너는 기본적으로 임시(ephemeral) 파일 시스템을 사용합니다. 컨테이너가 재시작되면 데이터가 손실되므로, 영구적인 데이터 저장이 필요한 경우 볼륨(Volume)을 사용해야 합니다.

## 볼륨의 필요성

* **데이터 영속성**: 컨테이너 재시작 시에도 데이터 유지
* **컨테이너 간 데이터 공유**: 같은 Pod 내 컨테이너들이 데이터 공유
* **설정 파일 마운트**: ConfigMap, Secret을 파일로 제공
* **호스트 시스템 접근**: 특정 경로의 호스트 데이터 사용

## 기본 볼륨 타입

### 1. emptyDir - 임시 볼륨

Pod가 생성될 때 빈 디렉토리로 시작하며, Pod가 삭제되면 데이터도 함께 삭제됩니다.

**사용 사례**:
- 임시 캐시 데이터
- 같은 Pod 내 컨테이너 간 데이터 공유
- 체크포인트나 중간 계산 결과 저장

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-emptydir
spec:
  containers:
  - name: nginx
    image: nginx:1.27
    volumeMounts:
    - name: cache-volume
      mountPath: /cache
  volumes:
  - name: cache-volume
    emptyDir: {}
```

### 2. hostPath - 호스트 경로 마운트

노드의 파일시스템 경로를 Pod에 마운트합니다. 주의해서 사용해야 합니다.

**주의사항**:
- 보안 위험이 있으므로 프로덕션 환경에서는 신중히 사용
- Pod가 다른 노드로 이동하면 이전 데이터에 접근 불가
- 노드의 파일시스템에 직접 영향을 줄 수 있음

```yaml
volumes:
- name: host-volume
  hostPath:
    path: /host-data-folder
    type: DirectoryOrCreate
```

**type 옵션**:
- `DirectoryOrCreate`: 디렉토리가 없으면 생성 (권한: 0755)
- `Directory`: 디렉토리가 반드시 존재해야 함
- `FileOrCreate`: 파일이 없으면 생성
- `File`: 파일이 반드시 존재해야 함

### 3. ConfigMap 볼륨

ConfigMap 데이터를 파일로 마운트합니다.

**ConfigMap 생성**:
```bash
# 파일로부터 ConfigMap 생성
cat <<EOF > app.conf
server.port=8080
server.host=localhost
app.name=MyApp
EOF

kubectl create configmap configmap-file --from-file=app.conf
```

**ConfigMap 볼륨 사용**:
```yaml
volumes:
- name: cm-volume
  configMap:
    name: configmap-file
```

**볼륨 마운트**:
```yaml
volumeMounts:
- name: cm-volume
  mountPath: /config
```

Pod 내에서 `/config/app.conf` 파일로 접근할 수 있습니다.

### 4. Secret 볼륨

Secret 데이터를 파일로 마운트합니다. 민감한 정보를 안전하게 전달할 때 사용합니다.

**Secret 생성**:
```bash
# 리터럴 값으로 Secret 생성
kubectl create secret generic secret-simple \
  --from-literal=username=admin \
  --from-literal=password=secret123
```

**Secret 볼륨 사용**:
```yaml
volumes:
- name: sec-volume
  secret:
    secretName: secret-simple

volumeMounts:
- name: sec-volume
  mountPath: /secretsimple
```

Pod 내에서 `/secretsimple/username`, `/secretsimple/password` 파일로 접근할 수 있습니다.

## Azure 스토리지 통합

AKS에서는 Azure의 관리형 스토리지 서비스를 Kubernetes 볼륨으로 사용할 수 있습니다.

### Azure Disk - 정적 프로비저닝

Azure Managed Disk를 직접 생성하고 Pod에 마운트합니다.

**1. Azure Disk 생성**:
```bash
# 리소스 그룹 및 클러스터 정보 확인
RESOURCE_GROUP="myResourceGroup"
LOCATION="koreacentral"
DISK_NAME="myAKSDisk"

# Azure Disk 생성 (8GB, Standard_LRS)
az disk create \
  --resource-group $RESOURCE_GROUP \
  --name $DISK_NAME \
  --size-gb 8 \
  --location $LOCATION \
  --sku Standard_LRS

# Disk의 Resource ID 확인
DISK_URI=$(az disk show \
  --resource-group $RESOURCE_GROUP \
  --name $DISK_NAME \
  --query id -o tsv)

echo "Disk URI: $DISK_URI"
```

**2. AKS 클러스터에 디스크 접근 권한 부여**:
```bash
# AKS 클러스터의 관리 ID 확인
CLUSTER_NAME="myAKSCluster"
AKS_IDENTITY=$(az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --query identityProfile.kubeletidentity.objectId -o tsv)

# 디스크에 대한 권한 부여
az role assignment create \
  --assignee $AKS_IDENTITY \
  --role Contributor \
  --scope $DISK_URI
```

**3. Deployment에 Azure Disk 마운트**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-with-disk
spec:
  replicas: 1  # Azure Disk는 단일 노드에만 마운트 가능
  selector:
    matchLabels:
      app: disk-app
  template:
    metadata:
      labels:
        app: disk-app
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        volumeMounts:
        - name: azure-disk
          mountPath: /data
      volumes:
      - name: azure-disk
        azureDisk:
          kind: Managed
          diskName: myAKSDisk
          diskURI: /subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Compute/disks/myAKSDisk
```

**Azure Disk 제약사항**:
- **ReadWriteOnce (RWO)**: 한 번에 하나의 노드에만 마운트 가능
- Pod가 여러 노드에 분산되면 일부 Pod는 Pending 상태로 남음
- 동시에 여러 Pod에서 읽기/쓰기가 필요한 경우 Azure Files 사용

### Azure Files - 동적 프로비저닝

Azure Files는 ReadWriteMany(RWX)를 지원하여 여러 노드에서 동시 접근이 가능합니다.

**1. PersistentVolumeClaim 생성**:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-file-storage-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: azurefile-csi
  resources:
    requests:
      storage: 10Gi
```

**2. Deployment에서 PVC 사용**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-with-files
spec:
  replicas: 3  # 여러 Pod에서 동시 접근 가능
  selector:
    matchLabels:
      app: file-app
  template:
    metadata:
      labels:
        app: file-app
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        volumeMounts:
        - name: azure-files
          mountPath: /shared-data
      volumes:
      - name: azure-files
        persistentVolumeClaim:
          claimName: dynamic-file-storage-pvc
```

## 스토리지 클래스

AKS는 기본적으로 여러 StorageClass를 제공합니다.

**사용 가능한 스토리지 클래스 확인**:
```bash
kubectl get storageclass
```

**주요 스토리지 클래스**:

| 이름 | 프로비저너 | 액세스 모드 | 용도 |
|------|-----------|------------|------|
| `managed-csi` (default) | Azure Disk CSI | RWO | 단일 Pod 블록 스토리지 |
| `managed-csi-premium` | Azure Disk CSI | RWO | 고성능 디스크 |
| `azurefile-csi` | Azure Files CSI | RWX | 공유 파일 스토리지 |
| `azurefile-csi-premium` | Azure Files CSI | RWX | 고성능 파일 공유 |

## 실습: 다양한 볼륨 타입 사용

### ConfigMap과 Secret 준비

```bash
# ConfigMap 생성
cat <<EOF > app-config.conf
log.level=info
max.connections=100
timeout=30
EOF

kubectl create configmap configmap-file --from-file=app-config.conf

# Secret 생성
kubectl create secret generic secret-simple \
  --from-literal=db_user=admin \
  --from-literal=db_password=P@ssw0rd123
```

### 여러 볼륨을 사용하는 Deployment

**workload-ephemeral.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-1-ephemeral
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
      - name: workload
        image: nginx:1.27
        ports:
        - containerPort: 80
        volumeMounts:
        - name: cm-volume
          mountPath: /config
        - name: sec-volume
          mountPath: /secretsimple
        - name: cache-volume
          mountPath: /cache
        - name: host-volume
          mountPath: /hostdata
      volumes:
      - name: cm-volume
        configMap:
          name: configmap-file
      - name: sec-volume
        secret:
          secretName: secret-simple
      - name: cache-volume
        emptyDir: {}
      - name: host-volume
        hostPath:
          path: /host-data-folder
          type: DirectoryOrCreate
```

**배포 및 확인**:
```bash
# Deployment 생성
kubectl apply -f workload-ephemeral.yaml

# Pod 확인
kubectl get pods

# Pod 내부에서 볼륨 확인
POD_NAME=$(kubectl get pod -l app=workload-1 -o jsonpath='{.items[0].metadata.name}')

# ConfigMap 파일 확인
kubectl exec $POD_NAME -- cat /config/app-config.conf

# Secret 파일 확인
kubectl exec $POD_NAME -- ls -l /secretsimple
kubectl exec $POD_NAME -- cat /secretsimple/db_user

# emptyDir 볼륨 테스트
kubectl exec $POD_NAME -- sh -c 'echo "test data" > /cache/test.txt'
kubectl exec $POD_NAME -- cat /cache/test.txt
```

### Azure Files PVC 실습

**1. PVC 생성**:
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-file-storage-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: azurefile-csi
  resources:
    requests:
      storage: 10Gi
EOF
```

**2. PVC 상태 확인**:
```bash
kubectl get pvc dynamic-file-storage-pvc
# STATUS가 Bound가 될 때까지 대기
```

**3. Deployment 생성**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-3-dynamic-file
spec:
  replicas: 3
  selector:
    matchLabels:
      app: file-app
  template:
    metadata:
      labels:
        app: file-app
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        volumeMounts:
        - name: shared-storage
          mountPath: /usr/share/nginx/html
      volumes:
      - name: shared-storage
        persistentVolumeClaim:
          claimName: dynamic-file-storage-pvc
```

**4. 공유 스토리지 테스트**:
```bash
# Deployment 배포
kubectl apply -f workload-dynamic-file.yaml

# Pod 확인
kubectl get pods -l app=file-app

# 첫 번째 Pod에 파일 생성
POD1=$(kubectl get pod -l app=file-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD1 -- sh -c 'echo "Hello from Pod 1" > /usr/share/nginx/html/index.html'

# 두 번째 Pod에서 파일 확인 (공유 스토리지이므로 같은 파일 보임)
POD2=$(kubectl get pod -l app=file-app -o jsonpath='{.items[1].metadata.name}')
kubectl exec $POD2 -- cat /usr/share/nginx/html/index.html
```

## 볼륨 타입 비교

| 볼륨 타입 | 영속성 | 공유 가능 | 사용 사례 |
|-----------|--------|----------|----------|
| emptyDir | Pod 수명 | Pod 내 컨테이너 간 | 임시 캐시, 컨테이너 간 공유 |
| hostPath | 노드 수명 | 같은 노드의 Pod | 노드 데이터 접근 (로그 등) |
| ConfigMap | 영구적 | 여러 Pod | 설정 파일 제공 |
| Secret | 영구적 | 여러 Pod | 인증 정보, 비밀번호 |
| Azure Disk | 영구적 | 단일 노드 (RWO) | 데이터베이스, 고성능 디스크 |
| Azure Files | 영구적 | 여러 노드 (RWX) | 공유 스토리지, 정적 콘텐츠 |

## 정리

```bash
# Deployment 삭제
kubectl delete deploy workload-1-ephemeral workload-3-dynamic-file

# PVC 삭제
kubectl delete pvc dynamic-file-storage-pvc

# ConfigMap, Secret 삭제
kubectl delete cm configmap-file
kubectl delete secret secret-simple
```

## 실습 과제

1. **ConfigMap 볼륨 실습**
   - 여러 개의 설정 파일을 포함하는 ConfigMap 생성
   - Nginx Pod에 마운트하여 커스텀 nginx.conf 사용

2. **emptyDir 볼륨 실습**
   - 두 개의 컨테이너가 emptyDir을 공유하는 Pod 생성
   - 한 컨테이너가 파일을 생성하고 다른 컨테이너가 읽도록 구성

3. **Azure Files 실습**
   - Azure Files PVC를 생성하고 여러 Pod에서 동시 접근
   - 한 Pod에서 파일을 생성하고 다른 Pod에서 읽기 확인

## 다음 단계

다음 섹션에서는 [고급 볼륨](./advanced-volumes)에서 PersistentVolume, PersistentVolumeClaim, 동적 프로비저닝에 대해 자세히 알아봅니다.

## 참고 자료

- [Kubernetes Volumes 공식 문서](https://kubernetes.io/docs/concepts/storage/volumes/)
- [AKS의 스토리지 옵션](https://learn.microsoft.com/ko-kr/azure/aks/concepts-storage)
- [Azure Disk CSI 드라이버](https://learn.microsoft.com/ko-kr/azure/aks/azure-disk-csi)
- [Azure Files CSI 드라이버](https://learn.microsoft.com/ko-kr/azure/aks/azure-files-csi)
