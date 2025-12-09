#!/usr/bin/bash

# AKS Best Practices 문서 검증 스크립트
# 문서의 YAML/Bash 코드 블록이 올바른지 검증

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

validate_yaml_syntax() {
    local file=$1
    log_info "YAML 문법 검증 중: $file"
    
    # yamllint 또는 기본 YAML 파서 사용
    if command -v yamllint &> /dev/null; then
        if yamllint -d relaxed "$file" > /dev/null 2>&1; then
            log_info "✓ YAML 문법 검증 성공: $file"
            return 0
        else
            log_error "✗ YAML 문법 검증 실패: $file"
            yamllint -d relaxed "$file"
            return 1
        fi
    else
        # yamllint가 없으면 Python으로 YAML 파싱 검증
        if python3 -c "import yaml; yaml.safe_load_all(open('$file'))" > /dev/null 2>&1; then
            log_info "✓ YAML 문법 검증 성공: $file"
            return 0
        else
            log_error "✗ YAML 문법 검증 실패: $file"
            python3 -c "import yaml; yaml.safe_load_all(open('$file'))"
            return 1
        fi
    fi
}

validate_bash_syntax() {
    local file=$1
    log_info "Bash 문법 검증 중: $file"
    
    if bash -n "$file" > /dev/null 2>&1; then
        log_info "✓ Bash 문법 검증 성공: $file"
        return 0
    else
        log_error "✗ Bash 문법 검증 실패: $file"
        bash -n "$file"
        return 1
    fi
}

# 메인 검증
main() {
    log_info "========================================="
    log_info "AKS Best Practices 문서 검증 시작"
    log_info "========================================="
    
    local failed=0
    
    # 1. Pod Security Standards YAML 검증
    log_info "\n[1/6] Pod Security Standards 검증..."
    cat > /tmp/pod-security-namespace.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: test-production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
EOF
    validate_yaml_syntax /tmp/pod-security-namespace.yaml || ((failed++))
    
    # 2. Restricted Security Context Pod 검증
    log_info "\n[2/6] Restricted Security Context Pod 검증..."
    cat > /tmp/secure-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: secure-app
  namespace: default
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: nginx:1.27
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      runAsUser: 1000
      capabilities:
        drop:
          - ALL
    volumeMounts:
    - name: tmp
      mountPath: /tmp
  volumes:
  - name: tmp
    emptyDir: {}
EOF
    validate_yaml_syntax /tmp/secure-pod.yaml || ((failed++))
    
    # 3. Network Policy 검증
    log_info "\n[3/6] Network Policy 검증..."
    cat > /tmp/network-policy.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
EOF
    validate_yaml_syntax /tmp/network-policy.yaml || ((failed++))
    
    # 4. ResourceQuota 검증
    log_info "\n[4/6] ResourceQuota 검증..."
    cat > /tmp/resource-quota.yaml <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: default
spec:
  hard:
    requests.cpu: "100"
    requests.memory: 200Gi
    limits.cpu: "200"
    limits.memory: 400Gi
    persistentvolumeclaims: "20"
    services.loadbalancers: "5"
EOF
    validate_yaml_syntax /tmp/resource-quota.yaml || ((failed++))
    
    # 5. LimitRange 검증
    log_info "\n[5/6] LimitRange 검증..."
    cat > /tmp/limit-range.yaml <<EOF
apiVersion: v1
kind: LimitRange
metadata:
  name: production-limits
  namespace: default
spec:
  limits:
  - max:
      cpu: "4"
      memory: 8Gi
    min:
      cpu: "100m"
      memory: 128Mi
    default:
      cpu: "500m"
      memory: 512Mi
    defaultRequest:
      cpu: "200m"
      memory: 256Mi
    type: Container
  - max:
      cpu: "8"
      memory: 16Gi
    min:
      cpu: "200m"
      memory: 256Mi
    type: Pod
EOF
    validate_yaml_syntax /tmp/limit-range.yaml || ((failed++))
    
    # 6. PodDisruptionBudget 검증
    log_info "\n[6/6] PodDisruptionBudget 검증..."
    cat > /tmp/pdb.yaml <<EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
  namespace: default
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: myapp
EOF
    validate_yaml_syntax /tmp/pdb.yaml || ((failed++))
    
    # 정리
    rm -f /tmp/pod-security-namespace.yaml \
          /tmp/secure-pod.yaml \
          /tmp/network-policy.yaml \
          /tmp/resource-quota.yaml \
          /tmp/limit-range.yaml \
          /tmp/pdb.yaml
    
    # 결과 출력
    log_info "\n========================================="
    log_info "검증 완료"
    log_info "========================================="
    
    if [ $failed -eq 0 ]; then
        log_info "✓ 모든 검증 통과!"
        return 0
    else
        log_error "✗ $failed 개의 검증 실패"
        return 1
    fi
}

main
