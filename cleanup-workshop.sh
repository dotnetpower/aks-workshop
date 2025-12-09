#!/usr/bin/bash

# AKS Workshop 리소스 정리 스크립트
# 테스트 중 생성된 모든 리소스를 정리

set -e

# 색상 정의
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 로깅 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 테스트 네임스페이스 정리
cleanup_test_namespaces() {
    log_info "테스트 네임스페이스 정리 중..."
    
    # test 라벨이 있는 모든 네임스페이스 찾기
    local namespaces=$(kubectl get namespaces -l test=workshop -o jsonpath='{.items[*].metadata.name}')
    
    if [ -z "$namespaces" ]; then
        log_info "정리할 테스트 네임스페이스가 없습니다."
        return 0
    fi
    
    for ns in $namespaces; do
        log_info "네임스페이스 삭제 중: $ns"
        kubectl delete namespace $ns --ignore-not-found=true
    done
    
    log_info "✓ 테스트 네임스페이스 정리 완료"
}

# Bookinfo 애플리케이션 정리
cleanup_bookinfo() {
    log_info "Bookinfo 애플리케이션 정리 중..."
    
    if kubectl get namespace bookinfo > /dev/null 2>&1; then
        log_info "네임스페이스 삭제: bookinfo"
        kubectl delete namespace bookinfo --ignore-not-found=true
        log_info "✓ Bookinfo 정리 완료"
    else
        log_info "Bookinfo 네임스페이스가 존재하지 않습니다."
    fi
}

# Istio 관련 리소스 정리
cleanup_istio_resources() {
    log_info "Istio 관련 리소스 정리 중..."
    
    # Kiali
    if helm list -n aks-istio-system | grep -q kiali-operator; then
        log_info "Kiali 제거 중..."
        helm uninstall kiali-operator -n aks-istio-system || true
    fi
    
    # 모니터링 도구 정리
    log_info "모니터링 도구 정리 중..."
    kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/addons/prometheus.yaml -n aks-istio-system --ignore-not-found=true || true
    kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/addons/grafana.yaml -n aks-istio-system --ignore-not-found=true || true
    kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.18/samples/addons/jaeger.yaml -n aks-istio-system --ignore-not-found=true || true
    
    log_info "✓ Istio 관련 리소스 정리 완료"
}

# ClusterInfo 정리
cleanup_clusterinfo() {
    log_info "ClusterInfo 정리 중..."
    
    if helm list -n clusterinfo | grep -q clusterinfo; then
        helm uninstall clusterinfo -n clusterinfo || true
        kubectl delete namespace clusterinfo --ignore-not-found=true
        log_info "✓ ClusterInfo 정리 완료"
    else
        log_info "ClusterInfo가 설치되어 있지 않습니다."
    fi
}

# 모든 테스트 리소스 정리
cleanup_all_test_resources() {
    log_info "모든 테스트 리소스 정리 중..."
    
    # scope=demo 라벨이 있는 모든 리소스 정리
    log_info "scope=demo 라벨이 있는 리소스 정리..."
    kubectl delete deployments,services,configmaps,secrets,pods -l scope=demo --all-namespaces --ignore-not-found=true || true
    
    # 특정 이름 패턴의 리소스 정리
    log_info "테스트 리소스 정리..."
    kubectl delete deployments,services,pods --all-namespaces -l app=test-workload --ignore-not-found=true || true
    kubectl delete deployments,services,pods --all-namespaces -l app=web --ignore-not-found=true || true
    
    log_info "✓ 모든 테스트 리소스 정리 완료"
}

# PVC 및 PV 정리
cleanup_storage() {
    log_info "스토리지 리소스 정리 중..."
    
    # 테스트 PVC 삭제
    kubectl delete pvc --all-namespaces -l test=workshop --ignore-not-found=true || true
    
    log_info "✓ 스토리지 리소스 정리 완료"
}

# CRD 정리 (선택적)
cleanup_crds() {
    if [ "$CLEANUP_CRDS" == "true" ]; then
        log_warning "Istio CRD 정리 중..."
        kubectl delete crd $(kubectl get crd -A | grep "istio.io" | awk '{print $1}') --ignore-not-found=true || true
        log_info "✓ CRD 정리 완료"
    else
        log_info "CRD 정리는 건너뜁니다 (CLEANUP_CRDS=true로 설정하여 실행 가능)"
    fi
}

# Istio Mesh 비활성화
disable_istio_mesh() {
    if [ "$DISABLE_MESH" == "true" ] && [ -n "$RESOURCE_GROUP" ] && [ -n "$CLUSTER" ]; then
        log_warning "Istio Mesh 비활성화 중..."
        log_warning "이 작업은 시간이 오래 걸릴 수 있습니다..."
        az aks mesh disable --resource-group ${RESOURCE_GROUP} --name ${CLUSTER} || true
        log_info "✓ Istio Mesh 비활성화 완료"
    else
        log_info "Istio Mesh 비활성화는 건너뜁니다 (DISABLE_MESH=true로 설정하여 실행 가능)"
    fi
}

# 클러스터 완전 삭제
delete_cluster() {
    if [ "$DELETE_CLUSTER" == "true" ] && [ -n "$RESOURCE_GROUP" ]; then
        log_error "========================================="
        log_error "경고: 클러스터를 완전히 삭제합니다!"
        log_error "========================================="
        read -p "정말로 리소스 그룹 '$RESOURCE_GROUP'를 삭제하시겠습니까? (yes/no): " confirmation
        
        if [ "$confirmation" == "yes" ]; then
            log_warning "리소스 그룹 삭제 중: $RESOURCE_GROUP"
            az group delete --name ${RESOURCE_GROUP} --yes --no-wait
            log_info "✓ 리소스 그룹 삭제 요청 완료 (백그라운드에서 진행됩니다)"
        else
            log_info "클러스터 삭제가 취소되었습니다."
        fi
    else
        log_info "클러스터 삭제는 건너뜁니다 (DELETE_CLUSTER=true로 설정하여 실행 가능)"
    fi
}

# 정리 확인
verify_cleanup() {
    log_info "========================================="
    log_info "정리 상태 확인"
    log_info "========================================="
    
    # 네임스페이스 확인
    local test_ns_count=$(kubectl get namespaces -l test=workshop --no-headers 2>/dev/null | wc -l)
    log_info "남아있는 테스트 네임스페이스: $test_ns_count"
    
    # Pod 확인
    local test_pods_count=$(kubectl get pods --all-namespaces -l scope=demo --no-headers 2>/dev/null | wc -l)
    log_info "남아있는 테스트 Pod: $test_pods_count"
    
    # PVC 확인
    local test_pvc_count=$(kubectl get pvc --all-namespaces -l test=workshop --no-headers 2>/dev/null | wc -l)
    log_info "남아있는 테스트 PVC: $test_pvc_count"
    
    if [ "$test_ns_count" -eq 0 ] && [ "$test_pods_count" -eq 0 ] && [ "$test_pvc_count" -eq 0 ]; then
        log_info "✓ 모든 테스트 리소스가 정리되었습니다!"
    else
        log_warning "일부 리소스가 아직 남아있습니다. 수동으로 확인하세요."
    fi
}

# 사용법 표시
usage() {
    cat <<EOF
AKS Workshop 리소스 정리 스크립트

사용법:
  $0 [OPTIONS]

옵션:
  --all                모든 리소스 정리 (테스트, Bookinfo, Istio)
  --test               테스트 리소스만 정리
  --bookinfo           Bookinfo 애플리케이션만 정리
  --istio              Istio 관련 리소스만 정리
  --disable-mesh       Istio Mesh 비활성화
  --cleanup-crds       Istio CRD 정리
  --delete-cluster     클러스터 완전 삭제
  --help               이 도움말 표시

환경 변수:
  RESOURCE_GROUP       Azure 리소스 그룹 이름
  CLUSTER              AKS 클러스터 이름
  CLEANUP_CRDS         CRD 정리 여부 (true/false)
  DISABLE_MESH         Mesh 비활성화 여부 (true/false)
  DELETE_CLUSTER       클러스터 삭제 여부 (true/false)

예제:
  # 모든 리소스 정리
  $0 --all

  # 테스트 리소스만 정리
  $0 --test

  # Istio Mesh 비활성화 및 CRD 정리
  DISABLE_MESH=true CLEANUP_CRDS=true $0 --istio

  # 클러스터 완전 삭제
  DELETE_CLUSTER=true $0 --delete-cluster
EOF
}

# 메인 함수
main() {
    log_info "========================================="
    log_info "AKS Workshop 리소스 정리"
    log_info "========================================="
    
    # 인자가 없으면 사용법 표시
    if [ $# -eq 0 ]; then
        usage
        exit 0
    fi
    
    # 인자 처리
    case "$1" in
        --all)
            cleanup_test_namespaces
            cleanup_all_test_resources
            cleanup_bookinfo
            cleanup_istio_resources
            cleanup_clusterinfo
            cleanup_storage
            cleanup_crds
            verify_cleanup
            ;;
        --test)
            cleanup_test_namespaces
            cleanup_all_test_resources
            cleanup_storage
            verify_cleanup
            ;;
        --bookinfo)
            cleanup_bookinfo
            ;;
        --istio)
            cleanup_istio_resources
            cleanup_crds
            ;;
        --disable-mesh)
            disable_istio_mesh
            ;;
        --cleanup-crds)
            CLEANUP_CRDS=true
            cleanup_crds
            ;;
        --delete-cluster)
            delete_cluster
            ;;
        --help)
            usage
            ;;
        *)
            log_error "알 수 없는 옵션: $1"
            usage
            exit 1
            ;;
    esac
    
    log_info "========================================="
    log_info "정리 완료!"
    log_info "========================================="
}

# 스크립트 실행
main "$@"
