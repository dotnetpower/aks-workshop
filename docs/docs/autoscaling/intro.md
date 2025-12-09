# 오토스케일링 및 리소스 관리

이 섹션에서는 Kubernetes의 리소스 관리와 다양한 오토스케일링 메커니즘을 실습합니다.

## 학습 목표

* 리소스 Requests/Limits 이해 및 설정
* LimitRange와 ResourceQuota를 통한 리소스 거버넌스
* HPA를 이용한 CPU/Memory 기반 오토스케일링
* KEDA를 활용한 이벤트 기반 오토스케일링
* 시간 기반 스케일링 전략

## 실습 순서

1. [리소스 관리](./resources) - Requests, Limits, LimitRange, ResourceQuota
2. [Horizontal Pod Autoscaler](./hpa) - CPU/Memory 기반 스케일링
3. [KEDA RabbitMQ 스케일링](./keda-rabbitmq) - 큐 기반 이벤트 스케일링
4. [KEDA Cron 스케일러](./keda-cron) - 시간 기반 스케일링

## 리소스 관리 개요

### Resource Requests vs Limits

| 구분 | Requests | Limits |
|------|----------|--------|
| 의미 | 보장된 리소스 | 최대 사용 가능 리소스 |
| 스케줄링 | 스케줄러가 고려 | 스케줄러 무시 |
| 초과 시 | N/A | CPU: Throttling, Memory: OOMKilled |

### QoS 클래스

Kubernetes는 리소스 설정에 따라 Pod에 QoS 클래스를 할당합니다:

| QoS 클래스 | 조건 | 우선순위 |
|-----------|------|---------|
| **Guaranteed** | Requests = Limits (모든 컨테이너) | 최고 |
| **Burstable** | Requests < Limits 또는 일부만 설정 | 중간 |
| **BestEffort** | Requests/Limits 미설정 | 최저 |

리소스 부족 시 BestEffort → Burstable → Guaranteed 순서로 제거됩니다.

## 오토스케일링 유형

### 1. Horizontal Pod Autoscaler (HPA)

Pod 개수를 자동으로 조정:

* **메트릭**: CPU, Memory, Custom Metrics
* **스케일링**: 워크로드 증가 시 Pod 추가
* **제한**: minReplicas, maxReplicas

### 2. Vertical Pod Autoscaler (VPA)

Pod의 리소스 요청/제한을 자동으로 조정:

* **메트릭**: 실제 사용량 기반
* **모드**: Auto, Initial, Off
* **주의**: Pod 재시작 필요

### 3. Cluster Autoscaler

노드 개수를 자동으로 조정:

* **트리거**: Pending Pod 발생 시
* **스케일 다운**: 노드 사용률 낮을 때
* **AKS 통합**: 노드 풀별 설정 가능

### 4. KEDA (Kubernetes Event-Driven Autoscaling)

이벤트 기반으로 Pod 자동 확장:

* **메트릭**: 메시지 큐, DB 쿼리, HTTP 요청 등
* **Scale to Zero**: 이벤트 없을 때 0으로 축소
* **다양한 Scaler**: RabbitMQ, Azure Service Bus, Prometheus 등

## AKS 오토스케일링 구성

### Cluster Autoscaler 활성화

```bash
# 클러스터 생성 시
az aks create \
  --resource-group myResourceGroup \
  --name myAKSCluster \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 5

# 기존 노드 풀에 활성화
az aks nodepool update \
  --resource-group myResourceGroup \
  --cluster-name myAKSCluster \
  --name nodepool1 \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 5
```

### Metrics Server 확인

HPA를 위해서는 Metrics Server가 필요합니다:

```bash
# Metrics Server 확인
kubectl get deployment metrics-server -n kube-system

# 없으면 설치
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

AKS는 기본적으로 Metrics Server가 설치되어 있습니다.

## 모니터링

### 리소스 사용량 확인

```bash
# 노드 리소스 사용량
kubectl top nodes

# Pod 리소스 사용량
kubectl top pods

# Namespace별 사용량
kubectl top pods -n <namespace>
```

### Azure Monitor

AKS는 Azure Monitor와 통합하여 상세한 메트릭을 제공합니다:

```bash
# Container Insights 활성화
az aks enable-addons \
  --resource-group myResourceGroup \
  --name myAKSCluster \
  --addons monitoring
```

## 베스트 프랙티스

1. **모든 Pod에 Requests/Limits 설정**: LimitRange로 기본값 적용
2. **Namespace별 ResourceQuota 설정**: 리소스 격리 및 제한
3. **QoS Guaranteed 사용**: 중요한 워크로드는 Requests = Limits
4. **HPA와 Cluster Autoscaler 함께 사용**: Pod와 노드 모두 자동 확장
5. **KEDA로 Scale to Zero**: 비용 최적화
6. **적절한 Stabilization Window 설정**: 불필요한 스케일링 방지

## 다음 단계

각 실습을 통해 리소스 관리와 다양한 오토스케일링 전략을 익히고, 실제 프로덕션 환경에서 효율적인 리소스 사용과 비용 최적화를 달성합니다.
