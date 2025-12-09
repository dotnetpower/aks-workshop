#!/usr/bin/bash

# AKS Workshop 테스트 스크립트
# 모든 실습 코드를 순서대로 테스트

set -e  # 오류 발생 시 스크립트 중단

# 색상 정의
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# 환경 변수 확인
check_environment() {
    log_info "환경 변수 확인 중..."
    
    if [ -z "$CLUSTER" ]; then
        log_error "CLUSTER 환경 변수가 설정되지 않았습니다."
        exit 1
    fi
    
    if [ -z "$RESOURCE_GROUP" ]; then
        log_error "RESOURCE_GROUP 환경 변수가 설정되지 않았습니다."
        exit 1
    fi
    
    log_info "환경 변수 확인 완료: CLUSTER=$CLUSTER, RESOURCE_GROUP=$RESOURCE_GROUP"
}

# 클러스터 연결 확인
check_cluster_connection() {
    log_info "클러스터 연결 확인 중..."
    
    if ! kubectl cluster-info > /dev/null 2>&1; then
        log_error "클러스터에 연결할 수 없습니다."
        exit 1
    fi
    
    log_info "클러스터 연결 확인 완료"
}

# 테스트 네임스페이스 생성
create_test_namespace() {
    local namespace=$1
    log_info "테스트 네임스페이스 생성: $namespace"
    
    kubectl create namespace $namespace --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace $namespace test=workshop --overwrite
}

# 리소스 대기
wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-default}
    local timeout=${4:-60}
    
    log_info "리소스 대기 중: $resource_type/$resource_name (namespace: $namespace, timeout: ${timeout}s)"
    
    kubectl wait --for=condition=ready $resource_type/$resource_name \
        -n $namespace --timeout=${timeout}s || true
}

# Module 1: Kubernetes 기초 테스트
test_module1_basic_deployments() {
    log_info "========================================="
    log_info "Module 1: 기본 Deployment 테스트"
    log_info "========================================="
    
    local namespace="test-basic-deploy"
    create_test_namespace $namespace
    
    # Deployment 생성
    log_info "Deployment 생성..."
    kubectl apply -n $namespace -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-workload
spec:
  replicas: 3
  selector:
    matchLabels:
      app: test-workload
  template:
    metadata:
      labels:
        app: test-workload
    spec:
      containers:
        - name: nginx
          image: nginx:1.21
          ports:
            - containerPort: 80
EOF
    
    # Deployment 확인
    wait_for_resource deployment test-workload $namespace
    
    local ready_replicas=$(kubectl get deployment test-workload -n $namespace -o jsonpath='{.status.readyReplicas}')
    if [ "$ready_replicas" == "3" ]; then
        log_info "✓ Deployment 테스트 성공"
    else
        log_error "✗ Deployment 테스트 실패: ready replicas = $ready_replicas"
        return 1
    fi
}

test_module1_services() {
    log_info "========================================="
    log_info "Module 1: Service 테스트"
    log_info "========================================="
    
    local namespace="test-service"
    create_test_namespace $namespace
    
    # Deployment 및 Service 생성
    kubectl apply -n $namespace -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-server
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:1.21
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web-service
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
EOF
    
    # Service 확인
    sleep 5
    local cluster_ip=$(kubectl get svc web-service -n $namespace -o jsonpath='{.spec.clusterIP}')
    
    if [ -n "$cluster_ip" ]; then
        log_info "✓ Service 테스트 성공 (ClusterIP: $cluster_ip)"
    else
        log_error "✗ Service 테스트 실패"
        return 1
    fi
}

test_module1_configmaps() {
    log_info "========================================="
    log_info "Module 1: ConfigMap 테스트"
    log_info "========================================="
    
    local namespace="test-configmap"
    create_test_namespace $namespace
    
    # ConfigMap 생성
    kubectl create configmap test-config \
        --from-literal=app.name=TestApp \
        --from-literal=app.version=1.0.0 \
        -n $namespace
    
    # ConfigMap을 사용하는 Pod 생성
    kubectl apply -n $namespace -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
    - name: test
      image: busybox
      command: ['sh', '-c', 'echo APP_NAME=\$APP_NAME && sleep 3600']
      env:
        - name: APP_NAME
          valueFrom:
            configMapKeyRef:
              name: test-config
              key: app.name
EOF
    
    sleep 10
    
    # Pod 로그 확인
    local logs=$(kubectl logs test-pod -n $namespace 2>/dev/null || echo "")
    
    if echo "$logs" | grep -q "APP_NAME=TestApp"; then
        log_info "✓ ConfigMap 테스트 성공"
    else
        log_error "✗ ConfigMap 테스트 실패"
        return 1
    fi
}

test_module1_secrets() {
    log_info "========================================="
    log_info "Module 1: Secret 테스트"
    log_info "========================================="
    
    local namespace="test-secret"
    create_test_namespace $namespace
    
    # Secret 생성
    kubectl create secret generic test-secret \
        --from-literal=username=admin \
        --from-literal=password=secretpass \
        -n $namespace
    
    # Secret을 사용하는 Pod 생성
    kubectl apply -n $namespace -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
    - name: test
      image: busybox
      command: ['sh', '-c', 'echo USERNAME=\$USERNAME && sleep 3600']
      env:
        - name: USERNAME
          valueFrom:
            secretKeyRef:
              name: test-secret
              key: username
EOF
    
    sleep 10
    
    # Pod 로그 확인
    local logs=$(kubectl logs test-pod -n $namespace 2>/dev/null || echo "")
    
    if echo "$logs" | grep -q "USERNAME=admin"; then
        log_info "✓ Secret 테스트 성공"
    else
        log_error "✗ Secret 테스트 실패"
        return 1
    fi
}

# Module 3: 고급 Kubernetes 테스트
test_module3_volumes() {
    log_info "========================================="
    log_info "Module 3: Volume 테스트"
    log_info "========================================="
    
    local namespace="test-volume"
    create_test_namespace $namespace
    
    # emptyDir 볼륨을 사용하는 Pod
    kubectl apply -n $namespace -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-volume-pod
spec:
  containers:
    - name: writer
      image: busybox
      command: ['sh', '-c', 'echo "test data" > /data/test.txt && sleep 3600']
      volumeMounts:
        - name: shared-data
          mountPath: /data
    - name: reader
      image: busybox
      command: ['sh', '-c', 'sleep 10 && cat /data/test.txt && sleep 3600']
      volumeMounts:
        - name: shared-data
          mountPath: /data
  volumes:
    - name: shared-data
      emptyDir: {}
EOF
    
    sleep 15
    
    # reader 컨테이너 로그 확인
    local logs=$(kubectl logs test-volume-pod -c reader -n $namespace 2>/dev/null || echo "")
    
    if echo "$logs" | grep -q "test data"; then
        log_info "✓ Volume 테스트 성공"
    else
        log_error "✗ Volume 테스트 실패"
        return 1
    fi
}

test_module3_probes() {
    log_info "========================================="
    log_info "Module 3: Probes 테스트"
    log_info "========================================="
    
    local namespace="test-probes"
    create_test_namespace $namespace
    
    # Liveness/Readiness Probe를 가진 Pod
    kubectl apply -n $namespace -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-probe-pod
spec:
  containers:
    - name: nginx
      image: nginx:1.21
      ports:
        - containerPort: 80
      livenessProbe:
        httpGet:
          path: /
          port: 80
        initialDelaySeconds: 3
        periodSeconds: 5
      readinessProbe:
        httpGet:
          path: /
          port: 80
        initialDelaySeconds: 3
        periodSeconds: 5
EOF
    
    sleep 10
    
    # Pod 상태 확인
    local ready=$(kubectl get pod test-probe-pod -n $namespace -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    
    if [ "$ready" == "True" ]; then
        log_info "✓ Probes 테스트 성공"
    else
        log_error "✗ Probes 테스트 실패"
        return 1
    fi
}

# Module 6: Pod 스케줄링 테스트
test_module6_node_selector() {
    log_info "========================================="
    log_info "Module 6: NodeSelector 테스트"
    log_info "========================================="
    
    local namespace="test-scheduling"
    create_test_namespace $namespace
    
    # NodeSelector를 사용하는 Pod (linux OS)
    kubectl apply -n $namespace -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-node-selector-pod
spec:
  containers:
    - name: nginx
      image: nginx:1.21
  nodeSelector:
    kubernetes.io/os: linux
EOF
    
    sleep 10
    
    # Pod가 스케줄되었는지 확인
    local phase=$(kubectl get pod test-node-selector-pod -n $namespace -o jsonpath='{.status.phase}')
    
    if [ "$phase" == "Running" ]; then
        log_info "✓ NodeSelector 테스트 성공"
    else
        log_error "✗ NodeSelector 테스트 실패 (phase: $phase)"
        return 1
    fi
}

# Module 7: 리소스 관리 테스트
test_module7_resources() {
    log_info "========================================="
    log_info "Module 7: Resource Requests/Limits 테스트"
    log_info "========================================="
    
    local namespace="test-resources"
    create_test_namespace $namespace
    
    # Resource requests/limits를 가진 Pod
    kubectl apply -n $namespace -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-resource-pod
spec:
  containers:
    - name: nginx
      image: nginx:1.21
      resources:
        requests:
          memory: "64Mi"
          cpu: "100m"
        limits:
          memory: "128Mi"
          cpu: "200m"
EOF
    
    sleep 10
    
    # Pod 상태 확인
    local phase=$(kubectl get pod test-resource-pod -n $namespace -o jsonpath='{.status.phase}')
    
    if [ "$phase" == "Running" ]; then
        log_info "✓ Resource Requests/Limits 테스트 성공"
    else
        log_error "✗ Resource Requests/Limits 테스트 실패"
        return 1
    fi
}

# 메인 테스트 실행
main() {
    log_info "========================================"
    log_info "AKS Workshop 테스트 시작"
    log_info "========================================"
    
    # 환경 확인
    check_environment
    check_cluster_connection
    
    # 테스트 실행
    local failed=0
    
    test_module1_basic_deployments || ((failed++))
    test_module1_services || ((failed++))
    test_module1_configmaps || ((failed++))
    test_module1_secrets || ((failed++))
    test_module3_volumes || ((failed++))
    test_module3_probes || ((failed++))
    test_module6_node_selector || ((failed++))
    test_module7_resources || ((failed++))
    
    # 결과 출력
    log_info "========================================"
    log_info "테스트 완료"
    log_info "========================================"
    
    if [ $failed -eq 0 ]; then
        log_info "✓ 모든 테스트 통과!"
        return 0
    else
        log_error "✗ $failed 개의 테스트 실패"
        return 1
    fi
}

# 스크립트 실행
main
