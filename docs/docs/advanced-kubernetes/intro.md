# 고급 Kubernetes 개념

이 섹션에서는 Kubernetes의 고급 기능과 프로덕션 환경에서 필요한 핵심 개념들을 실습합니다.

## 학습 목표

* Kubernetes 스토리지 시스템 (Volume, PV, PVC) 이해
* Ingress Controller를 통한 고급 라우팅 구성
* 애플리케이션 헬스 체크와 자동 복구 메커니즘 구현
* 컨테이너 초기화 및 다중 컨테이너 패턴 활용
* 배치 작업과 스케줄링 관리

## 실습 순서

1. [볼륨과 스토리지](./volumes) - 기본 볼륨 타입과 Azure 스토리지 통합
2. [고급 볼륨](./advanced-volumes) - PersistentVolume과 동적 프로비저닝
3. [Ingress Controller](./ingress) - HTTP/HTTPS 라우팅과 트래픽 관리
4. [헬스 체크](./probes) - Liveness, Readiness, Startup Probe
5. [Init Container](./init-containers) - 컨테이너 초기화 패턴
6. [Multi-Container Pods](./multi-container-pods) - 사이드카 및 멀티 컨테이너 패턴
7. [Jobs와 CronJobs](./jobs) - 배치 작업과 스케줄링

## 사전 요구사항

* Kubernetes 기초 섹션 완료
* AKS 클러스터가 정상적으로 동작 중
* `kubectl` 명령어 기본 사용법 숙지

## 주요 학습 내용

### 스토리지 관리
- 다양한 볼륨 타입 (emptyDir, hostPath, ConfigMap, Secret)
- Azure Disk와 Azure Files 통합
- PersistentVolume과 PersistentVolumeClaim
- 스토리지 클래스와 동적 프로비저닝

### 네트워킹
- Ingress Controller 설치 및 구성
- Path 기반 라우팅
- 네임스페이스별 트래픽 관리
- Default Backend 설정

### 애플리케이션 안정성
- 컨테이너 헬스 체크
- 자동 복구 메커니즘
- Init Container를 통한 초기화
- Multi-Container 패턴

### 작업 스케줄링
- 일회성 배치 작업 (Job)
- 주기적 작업 스케줄링 (CronJob)
- 병렬 실행 및 재시도 정책
