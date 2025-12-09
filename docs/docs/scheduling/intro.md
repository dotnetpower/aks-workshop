# Pod 스케줄링

이 섹션에서는 Kubernetes의 고급 스케줄링 메커니즘을 실습합니다.

## 학습 목표

* Node Affinity와 Pod Affinity/Anti-Affinity 이해
* Taint와 Toleration을 통한 노드 격리
* Topology Spread Constraints를 통한 고가용성 구성
* 스케줄링 전략을 활용한 워크로드 최적화

## 실습 순서

1. [Node Affinity와 Volume](./affinity-volume) - 노드 선호도와 볼륨 배치
2. [Anti-Affinity와 StatefulSet](./anti-affinity-stateful-set) - Pod 분산 배치
3. [Taint와 Toleration](./taint-tolerations) - 노드 격리 및 전용 할당
4. [Topology Spread Constraints](./topology-spread) - 토폴로지 기반 분산

## 스케줄링 개요

Kubernetes 스케줄러는 다음과 같은 단계로 Pod를 노드에 배치합니다:

1. **Filtering**: 조건을 만족하는 노드 선별
2. **Scoring**: 각 노드에 점수 부여
3. **Binding**: 가장 적합한 노드에 Pod 할당

### 스케줄링 제약 조건

| 메커니즘 | 용도 | 강제성 |
|---------|------|--------|
| NodeSelector | 간단한 노드 선택 | 필수 |
| Node Affinity | 선호도 기반 노드 선택 | 필수/선호 |
| Pod Affinity | Pod 간 근접 배치 | 필수/선호 |
| Pod Anti-Affinity | Pod 간 분산 배치 | 필수/선호 |
| Taint/Toleration | 노드 격리 및 전용화 | 필수 |
| Topology Spread | 토폴로지 기반 균등 분산 | 필수/선호 |

## AKS 특화 고려사항

### 가용성 영역

AKS는 여러 가용성 영역을 지원합니다:

```bash
# 가용성 영역이 있는 노드 풀 생성
az aks nodepool add \
  --resource-group myResourceGroup \
  --cluster-name myAKSCluster \
  --name mynodepool \
  --node-count 3 \
  --zones 1 2 3
```

### 노드 풀 레이블

AKS는 자동으로 다음 레이블을 설정합니다:

* `topology.kubernetes.io/zone`: 가용성 영역
* `topology.kubernetes.io/region`: 리전
* `kubernetes.azure.com/agentpool`: 노드 풀 이름

## 다음 단계

각 실습을 통해 다양한 스케줄링 전략을 학습하고, 실제 프로덕션 환경에서 워크로드를 최적화하는 방법을 익힙니다.
