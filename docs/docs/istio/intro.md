# Istio 서비스 메시

Istio는 마이크로서비스 애플리케이션의 트래픽 관리, 보안, 모니터링을 제공하는 오픈 소스 서비스 메시입니다.

## Istio란?

Istio는 다음과 같은 기능을 제공합니다:

- **트래픽 관리**: 세밀한 트래픽 라우팅 및 제어
- **보안**: 서비스 간 자동 mTLS 암호화
- **관찰성**: 분산 추적, 메트릭, 로그 수집
- **정책 적용**: 속도 제한, 할당량, 인증/인가

## Azure Kubernetes Service의 Istio 추가 기능

AKS는 Istio 서비스 메시를 관리형 추가 기능으로 제공하여 다음과 같은 이점을 제공합니다:

- **간편한 설치**: Azure CLI를 통한 원클릭 설치
- **자동 업그레이드**: Microsoft에서 관리하는 Istio 버전 업그레이드
- **통합 지원**: Azure 지원 팀의 공식 지원
- **성능 최적화**: AKS에 최적화된 설정

## 실습 내용

이 섹션에서는 다음 내용을 실습합니다:

### 1. Istio 환경 구성
- Istio 추가 기능 설치
- Ingress Gateway 설정
- Bookinfo 샘플 애플리케이션 배포

### 2. 트래픽 관리
- **Request Routing**: 특정 버전으로 트래픽 라우팅
- **Traffic Shifting**: 카나리 배포를 위한 가중치 기반 라우팅

### 3. 복원력 패턴
- **Fault Injection**: 장애 주입 테스트
- **Circuit Breaking**: 회로 차단기 패턴 구현

### 4. 보안
- **Authorization**: JWT 기반 인증 및 권한 부여

## 사전 요구 사항

Istio 실습을 시작하기 전에 다음을 완료해야 합니다:

1. **AKS 클러스터 생성**: [클러스터 구성](../setup/cluster-setup.md) 참조
2. **kubectl 설치**: Kubernetes CLI 도구
3. **Azure CLI**: 버전 2.57.0 이상

## 다음 단계

Istio 환경 구성을 시작하려면 [Bookinfo 샘플 애플리케이션 배포](../setup/bookinfo.md)를 참조하세요.

## 참고 자료

- [Istio 공식 문서](https://istio.io/latest/docs/)
- [Azure AKS Istio 추가 기능](https://learn.microsoft.com/ko-kr/azure/aks/istio-about)
- [Istio 서비스 메시 추가 기능 배포](https://learn.microsoft.com/ko-kr/azure/aks/istio-deploy-addon)
