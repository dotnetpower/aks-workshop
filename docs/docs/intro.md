---
sidebar_position: 1
---

# AKS Workshop

AKS를 구성하고 실습을 포함합니다.

## 워크샵 주제

### 🎯 Kubernetes 기초
* **Deployment 관리**: 기본 배포부터 고급 배포 전략까지
* **Service**: ClusterIP, NodePort, LoadBalancer
* **설정 관리**: ConfigMap과 Secret
* **배포 전략**: Blue-Green, Canary 배포

### 🚀 고급 Kubernetes
* **스토리지**: Volumes, PersistentVolume, PersistentVolumeClaim
* **네트워킹**: Ingress Controller, Path 기반 라우팅
* **안정성**: Liveness, Readiness, Startup Probes
* **고급 패턴**: Init Container, Multi-Container Pods
* **작업 스케줄링**: Jobs, CronJobs

### 📊 Pod 스케줄링
* **Affinity**: Node Affinity, Pod Affinity/Anti-Affinity
* **고급 스케줄링**: Taint & Toleration, Topology Spread
* **상태 관리**: StatefulSet을 통한 고가용성

### ⚡ 오토스케일링 & 리소스 관리
* **리소스 관리**: Requests/Limits, LimitRange, ResourceQuota
* **HPA**: CPU/Memory 기반 자동 스케일링
* **KEDA**: Event-driven Autoscaling
  * RabbitMQ 큐 기반 스케일링
  * Cron 기반 시간별 스케일링

### 🔧 Service Mesh (Istio)
* **Traffic Management**: Request Routing, Traffic Shifting
* **Resilience**: Fault Injection, Circuit Breaking
* **Security**: Authorization, mTLS
* **Observability**: Prometheus, Grafana, Jaeger, Kiali

## 🎓 학습 목표

이 워크샵을 완료하면 다음을 할 수 있습니다:

- ✅ AKS 클러스터 생성 및 관리
- ✅ Kubernetes 리소스 배포 및 운영
- ✅ 다양한 배포 전략 구현
- ✅ 스토리지 및 네트워킹 구성
- ✅ Pod 스케줄링 최적화
- ✅ 자동 스케일링 구현
- ✅ Istio를 통한 마이크로서비스 관리
- ✅ 모니터링 및 관찰성 구현

## 🚀 시작하기

이 워크샵을 시작하려면 다음 단계를 따라주세요:

1. **[사전 환경 설정](./setup/prerequisites)** - Azure CLI, kubectl, Helm 설치
2. **[클러스터 구성](./setup/cluster-setup)** - AKS 클러스터 생성 및 Istio 활성화
3. **[Bookinfo 배포](./setup/bookinfo)** - 샘플 애플리케이션 배포
4. **실습 진행** - 각 카테고리별 실습 문서 참고

## 💻 개발 환경 설정

### VS Code 디버깅

프로젝트 루트의 `.vscode/launch.json`에서 다음 작업을 실행할 수 있습니다:

- **Docusaurus: Start** - 개발 서버 시작 (F5)
- **Docusaurus: Build** - 프로덕션 빌드
- **Docusaurus: Serve** - 빌드된 사이트 미리보기
- **Test Workshop** - 워크샵 테스트 스크립트 실행
- **Cleanup Workshop** - 리소스 정리

### 로컬 문서 실행

```bash
cd docs
npm install
npm start
```

브라우저에서 `http://localhost:3000/aks-workshop/` 접속

## 📚 문서 구조

```
docs/
├── setup/                    # 환경 설정
├── kubernetes-basics/        # Kubernetes 기초
├── advanced-kubernetes/      # 고급 Kubernetes
├── scheduling/               # Pod 스케줄링
├── autoscaling/              # 오토스케일링
├── monitoring/               # 모니터링
├── istio/                     # Istio 실습
├── advanced/                 # 고급 팁
└── cleanup.md                # 리소스 정리
```

## 🧪 테스트 및 검증

### 자동 테스트

```bash
# 환경 변수 설정
source ./istio-env.sh

# 테스트 실행
./test-workshop.sh
```

### 리소스 정리

```bash
# 테스트 리소스만 정리
./cleanup-workshop.sh --test

# 모든 리소스 정리
./cleanup-workshop.sh --all
```

자세한 내용은 [TESTING.md](https://github.com/dotnetpower/aks-workshop/blob/main/TESTING.md) 참고

## 🤝 기여하기

이 프로젝트에 기여하고 싶으신가요?

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 라이선스

MIT License

## 📞 지원

문제가 발생하거나 질문이 있으시면:
- [GitHub Issues](https://github.com/dotnetpower/aks-workshop/issues)
- [GitHub Discussions](https://github.com/dotnetpower/aks-workshop/discussions)
