# AKS Workshop

[![GitHub Pages](https://img.shields.io/badge/docs-GitHub%20Pages-blue)](https://dotnetpower.github.io/aks-workshop/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.30-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Azure](https://img.shields.io/badge/Azure-AKS-0078D4?logo=microsoft-azure&logoColor=white)](https://azure.microsoft.com/ko-kr/services/kubernetes-service/)
[![Istio](https://img.shields.io/badge/Istio-1.24-466BB0?logo=istio&logoColor=white)](https://istio.io/)
[![Docusaurus](https://img.shields.io/badge/Docusaurus-3.9.2-3ECC5F?logo=docusaurus&logoColor=white)](https://docusaurus.io/)

Azure Kubernetes Service(AKS)와 Istio Service Mesh를 활용한 실전 Kubernetes 워크샵입니다.

## 📚 문서 사이트

워크샵 문서는 [GitHub Pages](https://dotnetpower.github.io/aks-workshop/)에서 확인할 수 있습니다.

## 🚀 워크샵 주제

### Kubernetes 기초
* Deployment, Service, ConfigMap, Secret
* Blue-Green 배포 및 Canary 배포

### 고급 Kubernetes
* Volumes와 스토리지 관리
* Ingress Controller
* Health Probes
* Init Container 및 Multi-Container Pods
* Jobs와 CronJobs

### Pod 스케줄링
* Node Affinity와 Anti-Affinity
* Taint와 Toleration
* Topology Spread Constraints
* StatefulSet

### 오토스케일링
* Resource Requests/Limits
* Horizontal Pod Autoscaler (HPA)
* KEDA (Event-driven Autoscaling)
  * RabbitMQ 기반 스케일링
  * Cron 기반 스케일링

### Service Mesh (Istio)
* Traffic Management (Request Routing, Traffic Shifting)
* Fault Injection
* Circuit Breaking
* Authorization
* Observability (Prometheus, Grafana, Jaeger, Kiali)

## 📖 빠른 시작

### 1. 사전 준비

```bash
# Azure CLI 설치
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# kubectl 설치
sudo az aks install-cli

# Helm 설치
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Azure 로그인
az login
```

### 2. 클러스터 생성

```bash
# 환경 변수 설정
source ./env.sh

# 리소스 그룹 생성
az group create --location $LOCATION --resource-group $RESOURCE_GROUP

# AKS 클러스터 생성 (약 5-10분 소요)
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER \
  --location $LOCATION \
  --node-count $NODE_COUNT \
  --kubernetes-version $K8S_VERSION \
  --network-plugin azure \
  --generate-ssh-keys

# 클러스터 자격 증명 가져오기
az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER --overwrite-existing

# 클러스터 확인
kubectl cluster-info
kubectl get nodes
```

### 3. 실습 시작

[워크샵 문서](https://dotnetpower.github.io/aks-workshop/)를 따라 실습을 진행하세요.

## 🧪 테스트

상세한 테스트 가이드는 [TEST_GUIDE.md](./TEST_GUIDE.md)를 참조하세요.

### 테스트 결과

✅ **모든 예제 코드가 검증되었습니다!** 

최신 테스트 결과는 [TEST_RESULTS.md](./TEST_RESULTS.md)에서 확인할 수 있습니다.

- **테스트 일시**: 2025-12-09
- **성공률**: 8/8 (100%)
- **테스트 항목**: Deployment, Service, ConfigMap, Secret, Volume, Probes, NodeSelector, Resource Limits

### 자동 테스트 실행

```bash
# 환경 변수 설정
source ./env.sh

# 테스트 실행 (결과를 파일로 저장)
./test-workshop.sh 2>&1 | tee test-results.log
```

### 테스트 범위

- ✅ **Module 1**: Kubernetes 기초 (Deployment, Service, ConfigMap, Secret)
- ✅ **Module 3**: 고급 Kubernetes (Volumes, Probes)
- ✅ **Module 6**: Pod 스케줄링 (NodeSelector, Affinity, Taints)
- ✅ **Module 7**: 오토스케일링 (Resource Limits, HPA)

### 리소스 정리

```bash
# 테스트 리소스만 정리
./cleanup-workshop.sh --test

# Bookinfo 애플리케이션 정리
./cleanup-workshop.sh --bookinfo

# Istio 리소스 정리
./cleanup-workshop.sh --istio

# 모든 리소스 정리
./cleanup-workshop.sh --all

# 클러스터 완전 삭제
./cleanup-workshop.sh --delete-cluster
```

## 📁 프로젝트 구조

```
.
├── docs/                          # Docusaurus 문서
│   ├── docs/
│   │   ├── setup/                 # 환경 설정
│   │   ├── kubernetes-basics/     # Kubernetes 기초
│   │   ├── advanced-kubernetes/   # 고급 Kubernetes
│   │   ├── scheduling/            # Pod 스케줄링
│   │   ├── autoscaling/           # 오토스케일링
│   │   ├── monitoring/            # 모니터링
│   │   ├── istio/                 # Istio 실습
│   │   └── advanced/              # 고급 팁
│   ├── src/                       # React 컴포넌트
│   └── static/                    # 이미지 및 정적 파일
├── images/                        # 문서 이미지
├── test-workshop.sh               # 자동 테스트 스크립트
├── cleanup-workshop.sh            # 리소스 정리 스크립트
├── env.sh                         # 환경 변수 설정
├── TEST_GUIDE.md                  # 상세 테스트 가이드
└── README.md                      # 이 파일
```

## 🛠️ 로컬에서 문서 실행

### 개발 모드

```bash
cd docs
npm install
npm start
```

브라우저에서 `http://localhost:3000/aks-workshop/`로 자동 접속됩니다.

### 프로덕션 빌드

```bash
cd docs
npm run build
npm run serve
```

## 🎯 학습 목표

이 워크샵을 완료하면 다음을 할 수 있습니다:

- ✅ AKS 클러스터 생성 및 관리
- ✅ Kubernetes 리소스 배포 및 운영
- ✅ 다양한 배포 전략 구현 (Blue-Green, Canary)
- ✅ 스토리지 및 네트워킹 구성
- ✅ Pod 스케줄링 최적화
- ✅ 자동 스케일링 구현 (HPA, KEDA)
- ✅ Istio를 통한 마이크로서비스 관리
- ✅ 모니터링 및 관찰성 구현

## 🤝 기여

이슈나 PR은 언제나 환영합니다!

### 기여 방법

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### 문서 작성 가이드라인

* 각 문서는 한국어로 작성합니다
* 실습 예제와 YAML 파일을 포함합니다
* 단계별 명령어와 예상 결과를 제공합니다
* 실습 과제 섹션을 추가합니다
* 모든 코드는 테스트를 거쳐야 합니다

## 📄 라이선스

MIT License - 자유롭게 사용하고 수정할 수 있습니다.

## 📞 지원

* 문제 보고: [GitHub Issues](https://github.com/dotnetpower/aks-workshop/issues)
* 질문 및 토론: [GitHub Discussions](https://github.com/dotnetpower/aks-workshop/discussions)

## 📚 참고 자료

* [Kubernetes 공식 문서](https://kubernetes.io/docs/)
* [Azure AKS 문서](https://learn.microsoft.com/ko-kr/azure/aks/)
* [Istio 공식 문서](https://istio.io/latest/docs/)
* [Docusaurus 문서](https://docusaurus.io/)

---

Made with ❤️ for Kubernetes learners



