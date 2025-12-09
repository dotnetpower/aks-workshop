# 클러스터 구성

## 환경 변수 설정

프로젝트 루트에 있는 `env.sh` 파일을 사용합니다:

```bash title="env.sh"
#!/bin/bash
# AKS 클러스터 기본 환경 변수
export RESOURCE_GROUP=aks-workshop-rg
export CLUSTER=aks-workshop
export LOCATION=koreacentral
export K8S_VERSION=1.32.9
export NODE_COUNT=3
```

환경 변수를 로드합니다:

```bash
source ./env.sh
```

## 리소스 그룹 및 클러스터 생성

```bash
# 리소스 그룹 생성
az group create --location $LOCATION --resource-group $RESOURCE_GROUP

# AKS 클러스터 생성 [약 5-10분 소요]
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --location $LOCATION \
  --node-count $NODE_COUNT \
  --kubernetes-version $K8S_VERSION \
  --network-plugin azure \
  --generate-ssh-keys

# 자격 증명 가져오기
az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER --overwrite-existing
```

## 클러스터 확인

```bash
# 클러스터 정보 확인
kubectl cluster-info

# 노드 확인
kubectl get nodes

# 네임스페이스 확인
kubectl get namespaces
```
