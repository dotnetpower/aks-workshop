# 고급 볼륨 관리

이 섹션에서는 Kubernetes의 고급 스토리지 개념인 PersistentVolume(PV)과 PersistentVolumeClaim(PVC)을 다룹니다. 동적 프로비저닝을 통해 스토리지를 자동으로 생성하고 관리하는 방법을 학습합니다.

## PersistentVolume과 PersistentVolumeClaim

### 개념 이해

**PersistentVolume (PV)**:
- 클러스터 관리자가 프로비저닝한 스토리지 리소스
- 클러스터 레벨 리소스 (네임스페이스에 속하지 않음)
- 물리적 스토리지의 추상화

**PersistentVolumeClaim (PVC)**:
- 사용자의 스토리지 요청
- 네임스페이스 레벨 리소스
- PV를 사용하기 위한 "청구서"

**관계**:
```
사용자 (Pod) → PVC 요청 → PV 바인딩 → 실제 스토리지 (Azure Disk/Files)
```

### PV와 PVC의 라이프사이클

1. **Provisioning (프로비저닝)**
   - **정적**: 관리자가 PV를 미리 생성
   - **동적**: StorageClass를 통해 자동 생성

2. **Binding (바인딩)**
   - PVC가 적절한 PV를 찾아 바인딩
   - 1:1 관계 유지

3. **Using (사용)**
   - Pod가 PVC를 볼륨으로 마운트하여 사용

4. **Reclaiming (회수)**
   - PVC 삭제 후 PV 처리 방법
   - **Retain**: PV 유지 (수동 정리 필요)
   - **Delete**: PV와 함께 스토리지 삭제
   - **Recycle**: 데이터 삭제 후 재사용 (deprecated)

## 액세스 모드 (Access Modes)

| 모드 | 약자 | 설명 | Azure 스토리지 |
|------|------|------|----------------|
| ReadWriteOnce | RWO | 단일 노드에서 읽기/쓰기 | Azure Disk |
| ReadOnlyMany | ROX | 여러 노드에서 읽기만 가능 | Azure Files (읽기 전용) |
| ReadWriteMany | RWX | 여러 노드에서 읽기/쓰기 | Azure Files |
| ReadWriteOncePod | RWOP | 단일 Pod에서만 읽기/쓰기 | Kubernetes 1.22+ |

## 동적 프로비저닝

StorageClass를 사용하면 PVC 생성 시 자동으로 PV가 생성됩니다.

### AKS의 기본 StorageClass

**확인**:
```bash
kubectl get storageclass
```

**출력 예시**:
```
NAME                    PROVISIONER          RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
azurefile-csi           file.csi.azure.com   Delete          Immediate              true
azurefile-csi-premium   file.csi.azure.com   Delete          Immediate              true
default (default)       disk.csi.azure.com   Delete          WaitForFirstConsumer   true
managed-csi             disk.csi.azure.com   Delete          WaitForFirstConsumer   true
managed-csi-premium     disk.csi.azure.com   Delete          WaitForFirstConsumer   true
```

**주요 속성**:
- **PROVISIONER**: 스토리지 프로비저너 (CSI 드라이버)
- **RECLAIMPOLICY**: PVC 삭제 시 PV 처리 방법
  - `Delete`: PV와 Azure 스토리지 자동 삭제
  - `Retain`: PV 유지, 수동 정리 필요
- **VOLUMEBINDINGMODE**: PV 바인딩 시점
  - `Immediate`: PVC 생성 즉시 바인딩
  - `WaitForFirstConsumer`: Pod가 스케줄링될 때까지 대기
- **ALLOWVOLUMEEXPANSION**: 볼륨 확장 가능 여부

## 실습 1: Azure Disk PVC (ReadWriteOnce)

### PVC 생성

**pvc-volume-disk.yaml**:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-volume-disk
spec:
  storageClassName: managed-csi
  accessModes:
    - ReadWriteOnce  # 단일 노드에만 마운트 가능
  resources:
    requests:
      storage: 8Gi
```

**배포**:
```bash
kubectl apply -f pvc-volume-disk.yaml

# PVC 상태 확인
kubectl get pvc pvc-volume-disk
```

**초기 상태**:
```
NAME              STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
pvc-volume-disk   Pending                                      managed-csi
```

`Pending` 상태인 이유: `WaitForFirstConsumer` 모드이므로 Pod가 생성될 때까지 대기합니다.

### Deployment 생성

**pvc-volume-dep.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pvc-volume-dep
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pvc-app
  template:
    metadata:
      labels:
        app: pvc-app
    spec:
      containers:
      - name: nginx
        image: nginx:1.18
        ports:
        - containerPort: 80
        volumeMounts:
        - name: data-volume
          mountPath: /data
      volumes:
      - name: data-volume
        persistentVolumeClaim:
          claimName: pvc-volume-disk
```

**배포**:
```bash
kubectl apply -f pvc-volume-dep.yaml

# Pod 상태 확인
kubectl get pods -l app=pvc-app

# PVC 상태 재확인
kubectl get pvc pvc-volume-disk
```

**바인딩 후 상태**:
```
NAME              STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
pvc-volume-disk   Bound    pvc-a1b2c3d4-e5f6-7890-abcd-ef1234567890   8Gi        RWO            managed-csi
```

### ReadWriteOnce의 제약사항 테스트

**레플리카 증가**:
```bash
# 40개로 증가
kubectl scale --replicas=40 deploy/pvc-volume-dep

# Pod 상태 확인
kubectl get pods -l app=pvc-app -o wide
```

**결과 관찰**:
- 같은 노드에 스케줄링된 Pod만 `Running` 상태
- 다른 노드에 스케줄링된 Pod는 `Pending` 상태로 남음

**Pending Pod의 이벤트 확인**:
```bash
# Pending Pod 찾기
PENDING_POD=$(kubectl get pod -l app=pvc-app --field-selector=status.phase=Pending -o jsonpath='{.items[0].metadata.name}')

# 이벤트 확인
kubectl describe pod $PENDING_POD
```

**에러 메시지 예시**:
```
Events:
  Type     Reason            Message
  ----     ------            -------
  Warning  FailedAttachVolume  Multi-Attach error for volume "pvc-a1b2c3d4..." 
                               Volume is already exclusively attached to one node and can't be attached to another
```

**설명**:
- Azure Disk는 ReadWriteOnce(RWO) 액세스 모드
- 한 번에 하나의 노드에만 연결 가능
- 같은 노드의 여러 Pod는 공유 가능
- 다른 노드의 Pod는 연결 불가

**레플리카 조정**:
```bash
# 적절한 수로 조정 (노드 수 이하)
kubectl scale --replicas=3 deploy/pvc-volume-dep
```

## 실습 2: 데이터 영속성 확인

### 데이터 쓰기

```bash
# 실행 중인 Pod 확인
POD_NAME=$(kubectl get pod -l app=pvc-app -o jsonpath='{.items[0].metadata.name}')

# 데이터 쓰기
kubectl exec $POD_NAME -- sh -c 'echo "Persistent Data - $(date)" > /data/test.txt'
kubectl exec $POD_NAME -- cat /data/test.txt
```

### Pod 재시작 후 데이터 확인

```bash
# Pod 삭제 (Deployment가 자동으로 재생성)
kubectl delete pod $POD_NAME

# 새 Pod가 생성될 때까지 대기
kubectl wait --for=condition=Ready pod -l app=pvc-app --timeout=60s

# 새 Pod 이름 확인
NEW_POD=$(kubectl get pod -l app=pvc-app -o jsonpath='{.items[0].metadata.name}')

# 데이터가 유지되는지 확인
kubectl exec $NEW_POD -- cat /data/test.txt
```

데이터가 그대로 유지됩니다!

### Deployment 삭제 후에도 데이터 유지

```bash
# Deployment 삭제
kubectl delete deploy pvc-volume-dep

# PVC는 여전히 존재
kubectl get pvc pvc-volume-disk

# PV 확인
PV_NAME=$(kubectl get pvc pvc-volume-disk -o jsonpath='{.spec.volumeName}')
kubectl get pv $PV_NAME
```

**재배포 후 데이터 확인**:
```bash
# Deployment 재생성
kubectl apply -f pvc-volume-dep.yaml

# Pod 준비 대기
kubectl wait --for=condition=Ready pod -l app=pvc-app --timeout=60s

# 데이터 확인
POD_NAME=$(kubectl get pod -l app=pvc-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD_NAME -- cat /data/test.txt
```

이전에 저장한 데이터가 그대로 남아 있습니다!

## 실습 3: 볼륨 확장

AKS의 StorageClass는 기본적으로 볼륨 확장을 지원합니다.

### 현재 크기 확인

```bash
kubectl get pvc pvc-volume-disk
# CAPACITY: 8Gi
```

### PVC 크기 증가

```bash
# PVC 수정
kubectl patch pvc pvc-volume-disk -p '{"spec":{"resources":{"requests":{"storage":"16Gi"}}}}'

# 상태 확인
kubectl get pvc pvc-volume-disk -w
```

**볼륨 확장 과정**:
1. PVC의 요청 크기 변경
2. 클라우드 프로바이더가 디스크 크기 조정
3. 파일시스템 자동 확장
4. Pod 재시작 없이 적용 (온라인 확장)

**확장 확인**:
```bash
# Pod 내부에서 확인
POD_NAME=$(kubectl get pod -l app=pvc-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD_NAME -- df -h /data
```

## 실습 4: 커스텀 StorageClass

특정 요구사항에 맞는 StorageClass를 생성할 수 있습니다.

### Premium SSD StorageClass

**storageclass-premium.yaml**:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: managed-premium-retain
provisioner: disk.csi.azure.com
parameters:
  skuName: Premium_LRS  # Premium SSD
  kind: Managed
reclaimPolicy: Retain  # PVC 삭제 시에도 PV 유지
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

**생성**:
```bash
kubectl apply -f storageclass-premium.yaml

# 확인
kubectl get storageclass managed-premium-retain
```

### 커스텀 StorageClass 사용

**pvc-premium.yaml**:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-premium-disk
spec:
  storageClassName: managed-premium-retain
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 32Gi
```

## PV/PVC 관리 명령어

### 상태 확인

```bash
# PVC 목록
kubectl get pvc

# PVC 상세 정보
kubectl describe pvc pvc-volume-disk

# PV 목록
kubectl get pv

# PV 상세 정보
kubectl describe pv <pv-name>
```

### PVC 사용 현황

```bash
# 특정 PVC를 사용하는 Pod 찾기
kubectl get pods --all-namespaces -o json | \
  jq -r '.items[] | 
    select(.spec.volumes[]? | .persistentVolumeClaim.claimName=="pvc-volume-disk") | 
    .metadata.namespace + "/" + .metadata.name'
```

### Azure Portal에서 확인

```bash
# PV의 Azure Disk 이름 확인
kubectl get pv <pv-name> -o jsonpath='{.spec.csi.volumeHandle}'
```

이 정보를 Azure Portal의 Disks 섹션에서 확인할 수 있습니다.

## ReclaimPolicy 이해

### Delete (기본값)

```yaml
reclaimPolicy: Delete
```

- PVC 삭제 시 PV도 자동 삭제
- Azure에서 실제 디스크도 삭제됨
- 비용 절감에 유리

### Retain

```yaml
reclaimPolicy: Retain
```

- PVC 삭제 후에도 PV 유지
- Azure 디스크는 그대로 유지
- 데이터 보존이 중요한 경우 사용

**Retain 테스트**:
```bash
# PVC 삭제
kubectl delete pvc pvc-volume-disk

# PV는 Released 상태로 유지
kubectl get pv

# 수동으로 PV 삭제 필요
kubectl delete pv <pv-name>
```

## 볼륨 스냅샷

AKS는 볼륨 스냅샷을 지원하여 백업과 복제를 쉽게 할 수 있습니다.

### VolumeSnapshot 생성

**volumesnapshot.yaml**:
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: pvc-disk-snapshot
spec:
  volumeSnapshotClassName: csi-azuredisk-vsc
  source:
    persistentVolumeClaimName: pvc-volume-disk
```

### 스냅샷에서 PVC 복원

**pvc-from-snapshot.yaml**:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-restored
spec:
  storageClassName: managed-csi
  dataSource:
    name: pvc-disk-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 8Gi
```

## 정리

```bash
# Deployment 삭제
kubectl delete deploy pvc-volume-dep

# PVC 삭제 (Delete 정책이면 PV도 자동 삭제)
kubectl delete pvc pvc-volume-disk

# StorageClass 삭제 (필요시)
kubectl delete storageclass managed-premium-retain
```

## 베스트 프랙티스

1. **적절한 액세스 모드 선택**
   - 단일 Pod: ReadWriteOnce (Azure Disk) - 고성능
   - 다중 Pod: ReadWriteMany (Azure Files) - 공유 필요 시

2. **적절한 StorageClass 선택**
   - 개발/테스트: Standard_LRS (저렴한 비용)
   - 프로덕션: Premium_LRS (높은 성능)

3. **ReclaimPolicy 설정**
   - 개발 환경: Delete (자동 정리)
   - 프로덕션: Retain (데이터 보호)

4. **볼륨 크기 계획**
   - 초기 크기를 충분히 할당
   - 확장 가능하지만 축소는 불가
   - 모니터링 및 알림 설정

5. **백업 전략**
   - 중요 데이터는 정기적 스냅샷 생성
   - 재해 복구 계획 수립

## 실습 과제

1. **PVC 생성 및 사용**
   - 10Gi Azure Disk PVC 생성
   - Deployment에 마운트하여 데이터 쓰기
   - Pod 재시작 후 데이터 영속성 확인

2. **볼륨 확장 실습**
   - 8Gi PVC를 16Gi로 확장
   - 확장 과정 모니터링
   - Pod 내부에서 크기 확인

3. **ReclaimPolicy 테스트**
   - Retain 정책의 StorageClass 생성
   - PVC 생성 및 데이터 쓰기
   - PVC 삭제 후 PV 상태 확인

4. **ReadWriteOnce 제약사항 확인**
   - Azure Disk PVC 생성
   - 여러 레플리카로 Deployment 생성
   - 일부 Pod가 Pending 상태로 남는 이유 분석

## 다음 단계

다음 섹션에서는 [Ingress Controller](./ingress)를 통한 HTTP/HTTPS 라우팅과 트래픽 관리 방법을 학습합니다.

## 참고 자료

- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [AKS의 동적 PV 생성](https://learn.microsoft.com/ko-kr/azure/aks/azure-disk-csi)
- [볼륨 스냅샷](https://learn.microsoft.com/ko-kr/azure/aks/azure-disk-volume-snapshot)
- [스토리지 클래스](https://kubernetes.io/docs/concepts/storage/storage-classes/)
