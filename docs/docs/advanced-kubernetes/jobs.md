# Jobs와 CronJobs

Kubernetes에서 일회성 작업이나 주기적인 배치 작업을 실행하기 위한 리소스입니다. Deployment와 달리 작업이 완료되면 종료됩니다.

## Job vs Deployment

### Deployment
- **목적**: 지속적으로 실행되는 애플리케이션
- **재시작**: 컨테이너가 종료되면 재시작
- **예시**: 웹 서버, API 서버, 데이터베이스

### Job
- **목적**: 한 번 실행하고 완료되는 작업
- **재시작**: 성공적으로 완료되면 재시작 안 함
- **예시**: 데이터 처리, 백업, 마이그레이션

## Job 리소스

### 기본 개념

Job은 하나 이상의 Pod를 생성하고 지정된 수의 Pod가 성공적으로 완료될 때까지 실행합니다.

**특징**:
- Pod가 성공하면 Job 완료
- Pod가 실패하면 재시도 (설정에 따라)
- 병렬 실행 지원
- 완료 후 Pod 유지 (로그 확인 가능)

### Job 매개변수

| 매개변수 | 설명 | 기본값 |
|---------|------|--------|
| `completions` | 성공해야 하는 Pod 수 | 1 |
| `parallelism` | 동시에 실행할 Pod 수 | 1 |
| `backoffLimit` | 실패 허용 횟수 | 6 |
| `activeDeadlineSeconds` | 전체 작업 제한 시간 | 없음 |
| `ttlSecondsAfterFinished` | 완료 후 자동 삭제 시간 | 없음 |

## 실습 1: 기본 Job

### 간단한 카운트다운 Job

**countdown-job.yaml**:
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: countdown-job
spec:
  # Job 전체 설정
  completions: 10       # 총 10개의 Pod가 성공해야 완료
  parallelism: 4        # 동시에 4개의 Pod 실행
  backoffLimit: 3       # 3번 실패하면 중단
  activeDeadlineSeconds: 100  # 최대 100초 안에 완료
  ttlSecondsAfterFinished: 240  # 완료 후 240초 뒤 자동 삭제
  
  # Pod 템플릿
  template:
    metadata:
      name: countdown-job
      labels:
        app: countdown-job
        color: aqua
    spec:
      containers:
      - name: counter
        image: centos:7
        command:
        - "bin/bash"
        - "-c"
        - "for i in 9 8 7 6 5 4 3 2 1; do echo $i; sleep 2; done"
      
      restartPolicy: OnFailure  # Job에서는 Always 사용 불가
      nodeSelector:
        kubernetes.io/os: linux
```

**배포 및 관찰**:
```bash
# Job 생성
kubectl apply -f countdown-job.yaml

# Job 상태 확인
kubectl get jobs

# Job 상세 정보
kubectl describe job countdown-job

# Pod 실시간 확인
kubectl get pods -l app=countdown-job -w
```

**Job 진행 상황**:
```
NAME             COMPLETIONS   DURATION   AGE
countdown-job    0/10          5s         5s
countdown-job    4/10          20s        20s
countdown-job    8/10          40s        40s
countdown-job    10/10         60s        60s
```

**Pod 상태 변화**:
```
NAME                   READY   STATUS              RESTARTS   AGE
countdown-job-xxxxx    0/1     ContainerCreating   0          1s
countdown-job-xxxxx    1/1     Running             0          5s
countdown-job-xxxxx    0/1     Completed           0          25s
```

**관찰 포인트**:
1. **병렬 실행**: 처음에 4개의 Pod가 동시에 시작 (parallelism=4)
2. **순차 완료**: Pod가 완료되면 새 Pod 시작 (총 10개 완료까지)
3. **완료 유지**: Completed 상태의 Pod는 삭제되지 않음 (로그 확인 가능)
4. **자동 삭제**: 240초 후 Job과 Pod 자동 삭제

### Job 로그 확인

```bash
# 완료된 Pod 목록
kubectl get pods -l app=countdown-job --field-selector=status.phase=Succeeded

# 특정 Pod 로그
POD_NAME=$(kubectl get pods -l app=countdown-job -o jsonpath='{.items[0].metadata.name}')
kubectl logs $POD_NAME
```

**로그 출력**:
```
9
8
7
6
5
4
3
2
1
```

## 실습 2: Job 실패 및 재시도

### 의도적으로 실패하는 Job

**failing-job.yaml**:
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: failing-job
spec:
  completions: 1
  backoffLimit: 5  # 최대 5번 재시도
  template:
    spec:
      containers:
      - name: fail
        image: busybox
        command:
        - sh
        - -c
        - |
          echo "Attempt #$(cat /tmp/attempt 2>/dev/null || echo 0)"
          if [ ! -f /tmp/success ]; then
            # 60% 확률로 실패
            if [ $(( RANDOM % 10 )) -lt 6 ]; then
              echo "Failed!"
              exit 1
            fi
          fi
          echo "Success!"
          touch /tmp/success
      restartPolicy: OnFailure
```

**배포 및 관찰**:
```bash
kubectl apply -f failing-job.yaml

# Job 상태 확인
kubectl get job failing-job -w

# Pod 상태 확인 (재시작 횟수 증가)
kubectl get pods -l job-name=failing-job -w
```

**Pod 재시도**:
```
NAME               READY   STATUS    RESTARTS   AGE
failing-job-xxxx   1/1     Running   0          5s
failing-job-xxxx   0/1     Error     0          10s
failing-job-xxxx   1/1     Running   1          15s
failing-job-xxxx   0/1     Error     1          20s
failing-job-xxxx   1/1     Running   2          25s
failing-job-xxxx   0/1     Completed 2          30s
```

**restartPolicy 차이**:
- `OnFailure`: 같은 Pod를 재시작 (RESTARTS 증가)
- `Never`: 새로운 Pod 생성 (여러 Pod 생성)

## 실습 3: 병렬 처리 Job

### 데이터 병렬 처리

**parallel-job.yaml**:
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: parallel-processing
spec:
  completions: 20      # 총 20개 작업
  parallelism: 5       # 동시에 5개씩 처리
  template:
    spec:
      containers:
      - name: processor
        image: busybox
        command:
        - sh
        - -c
        - |
          # 작업 ID 생성 (Pod 이름 기반)
          TASK_ID=$(echo $HOSTNAME | grep -o '[0-9]*$')
          echo "Processing task #$TASK_ID"
          
          # 작업 시뮬레이션 (1-5초)
          DURATION=$(( RANDOM % 5 + 1 ))
          echo "Task will take $DURATION seconds"
          sleep $DURATION
          
          echo "Task #$TASK_ID completed!"
      restartPolicy: OnFailure
```

**배포 및 모니터링**:
```bash
kubectl apply -f parallel-job.yaml

# 동시 실행 Pod 확인
kubectl get pods -l job-name=parallel-processing --watch

# Job 진행률 확인
watch kubectl get job parallel-processing
```

**진행 상황**:
```
COMPLETIONS   DURATION
0/20          5s
5/20          15s
10/20         30s
15/20         45s
20/20         60s
```

## CronJob 리소스

### 기본 개념

CronJob은 정해진 일정에 따라 Job을 자동으로 생성합니다.

**사용 사례**:
- 백업 작업 (매일 자정)
- 리포트 생성 (매주 월요일)
- 데이터 정리 (매시간)
- 로그 아카이빙 (매일)

### Cron 스케줄 형식

```
┌─────────── 분 (0-59)
│ ┌───────── 시 (0-23)
│ │ ┌─────── 일 (1-31)
│ │ │ ┌───── 월 (1-12)
│ │ │ │ ┌─── 요일 (0-7, 0과 7은 일요일)
│ │ │ │ │
* * * * *
```

**예시**:
| 스케줄 | 설명 |
|--------|------|
| `* * * * *` | 매 분마다 |
| `*/5 * * * *` | 5분마다 |
| `0 * * * *` | 매 시각 정각 |
| `0 0 * * *` | 매일 자정 |
| `0 0 * * 0` | 매주 일요일 자정 |
| `0 0 1 * *` | 매월 1일 자정 |
| `30 2 * * 1-5` | 평일 오전 2:30 |

## 실습 4: 기본 CronJob

### 매분마다 실행되는 CronJob

**sample-cron-job.yaml**:
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: sample-cron-job
spec:
  schedule: "* * * * *"  # 매 분마다 실행
  successfulJobsHistoryLimit: 6  # 성공한 Job 6개 유지
  failedJobsHistoryLimit: 6      # 실패한 Job 6개 유지
  
  jobTemplate:
    spec:
      completions: 1
      ttlSecondsAfterFinished: 270  # 완료 후 270초 뒤 삭제
      
      template:
        metadata:
          labels:
            color: yellow
        spec:
          containers:
          - name: hello
            image: busybox
            args:
            - /bin/sh
            - -c
            - date; echo Hello from the Kubernetes cluster; sleep 3
          
          restartPolicy: OnFailure
          nodeSelector:
            kubernetes.io/os: linux
```

**배포 및 관찰**:
```bash
# CronJob 생성
kubectl apply -f sample-cron-job.yaml

# CronJob 확인
kubectl get cronjobs

# CronJob 상세 정보
kubectl describe cronjob sample-cron-job

# 생성된 Job 확인 (매분마다 새로운 Job 생성)
kubectl get jobs -w

# Pod 확인
kubectl get pods -l color=yellow -w
```

**CronJob 상태**:
```
NAME               SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
sample-cron-job    * * * * *     False     1        15s             2m
```

**생성된 Job들**:
```
NAME                          COMPLETIONS   DURATION   AGE
sample-cron-job-28398640      1/1           5s         2m
sample-cron-job-28398641      1/1           5s         1m
sample-cron-job-28398642      1/1           5s         30s
sample-cron-job-28398643      0/1           5s         5s
```

### 히스토리 관리

**Job 히스토리 확인**:
```bash
# 최근 Job 목록
kubectl get jobs --sort-by=.metadata.creationTimestamp

# 오래된 Job은 자동 삭제됨 (historyLimit 설정에 따라)
```

## 실습 5: 백업 CronJob

### 데이터베이스 백업 예제

**db-backup-cronjob.yaml**:
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-backup
spec:
  schedule: "0 2 * * *"  # 매일 오전 2시
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: mysql:5.7
            env:
            - name: BACKUP_DATE
              value: "$(date +%Y%m%d_%H%M%S)"
            command:
            - sh
            - -c
            - |
              echo "Starting backup at $(date)"
              
              # MySQL 덤프 (실제로는 실행 안 됨, 예시)
              # mysqldump -h mysql -u root -ppassword mydb > /backup/backup_${BACKUP_DATE}.sql
              
              echo "Creating backup file..."
              echo "Backup data $(date)" > /backup/backup_$(date +%Y%m%d_%H%M%S).txt
              
              echo "Backup completed at $(date)"
              ls -lh /backup/
            volumeMounts:
            - name: backup-storage
              mountPath: /backup
          
          restartPolicy: OnFailure
          
          volumes:
          - name: backup-storage
            emptyDir: {}  # 실제로는 PVC 사용 권장
```

**배포**:
```bash
kubectl apply -f db-backup-cronjob.yaml

# CronJob 확인
kubectl get cronjob db-backup
```

### 수동 Job 실행

스케줄을 기다리지 않고 즉시 Job을 생성:

```bash
# CronJob에서 즉시 Job 생성
kubectl create job --from=cronjob/db-backup manual-backup-1

# Job 확인
kubectl get job manual-backup-1

# 로그 확인
POD_NAME=$(kubectl get pods -l job-name=manual-backup-1 -o jsonpath='{.items[0].metadata.name}')
kubectl logs $POD_NAME
```

## CronJob 고급 설정

### 동시성 제어

**concurrencyPolicy**:
- `Allow` (기본값): 동시 실행 허용
- `Forbid`: 이전 Job이 완료되지 않으면 새 Job 건너뜀
- `Replace`: 이전 Job을 종료하고 새 Job 시작

**concurrency-policy.yaml**:
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: exclusive-job
spec:
  schedule: "*/2 * * * *"  # 2분마다
  concurrencyPolicy: Forbid  # 동시 실행 금지
  
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: long-task
            image: busybox
            command:
            - sh
            - -c
            - |
              echo "Starting long task at $(date)"
              sleep 180  # 3분 소요 (스케줄보다 길음)
              echo "Task completed at $(date)"
          restartPolicy: OnFailure
```

**동작**:
- 첫 번째 Job 시작 (2분 시점)
- 두 번째 스케줄 시점 (4분) - 이전 Job이 아직 실행 중이므로 건너뜀
- 첫 번째 Job 완료 (5분 시점)
- 세 번째 스케줄 시점 (6분) - 새 Job 시작

### 시작 기한 설정

**startingDeadlineSeconds**:

```yaml
spec:
  schedule: "0 2 * * *"
  startingDeadlineSeconds: 3600  # 1시간 이내에 시작 못하면 실패
```

**사용 사례**:
- 클러스터가 다운되어 스케줄을 놓친 경우
- 너무 오래된 작업은 실행하지 않음

### 일시 중지

```bash
# CronJob 일시 중지
kubectl patch cronjob sample-cron-job -p '{"spec":{"suspend":true}}'

# 확인
kubectl get cronjob sample-cron-job

# 재개
kubectl patch cronjob sample-cron-job -p '{"spec":{"suspend":false}}'
```

## 실습 6: 리포트 생성 CronJob

### 주간 리포트 예제

**weekly-report.yaml**:
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: weekly-report
spec:
  schedule: "0 9 * * 1"  # 매주 월요일 오전 9시
  timeZone: "Asia/Seoul"  # Kubernetes 1.25+
  
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: report-generator
            image: busybox
            command:
            - sh
            - -c
            - |
              echo "==================================="
              echo "Weekly Report - $(date)"
              echo "==================================="
              
              echo "Period: Last 7 days"
              echo "Generated: $(date)"
              
              # 실제로는 데이터 수집 및 리포트 생성
              echo "Total users: $(( RANDOM % 10000 ))"
              echo "Active users: $(( RANDOM % 5000 ))"
              echo "Revenue: $$(( RANDOM % 100000 ))"
              
              echo "==================================="
              echo "Report generation completed!"
          
          restartPolicy: OnFailure
```

## Job과 CronJob 관리

### Job 삭제

```bash
# 특정 Job 삭제
kubectl delete job countdown-job

# 완료된 모든 Job 삭제
kubectl delete jobs --field-selector status.successful=1

# 실패한 모든 Job 삭제
kubectl delete jobs --field-selector status.failed=1
```

### CronJob 관리

```bash
# CronJob 목록
kubectl get cronjobs

# 특정 CronJob에서 생성된 Job 확인
kubectl get jobs --selector=job-name=sample-cron-job

# CronJob 삭제 (생성된 Job도 함께 삭제)
kubectl delete cronjob sample-cron-job

# CronJob만 삭제 (생성된 Job은 유지)
kubectl delete cronjob sample-cron-job --cascade=orphan
```

## 모니터링 및 알림

### Job 완료 확인

```bash
# 완료된 Job 확인
kubectl get jobs --field-selector status.successful=1

# 실패한 Job 확인
kubectl get jobs --field-selector status.failed=1

# Job 상태 JSON으로 출력
kubectl get job countdown-job -o json | jq .status
```

### 이벤트 확인

```bash
# Job 이벤트
kubectl describe job countdown-job

# CronJob 이벤트
kubectl describe cronjob sample-cron-job
```

## 정리

```bash
# Job 삭제
kubectl delete job countdown-job failing-job parallel-processing

# CronJob 삭제
kubectl delete cronjob sample-cron-job db-backup weekly-report exclusive-job
```

## 베스트 프랙티스

### 1. 적절한 리소스 제한

```yaml
spec:
  template:
    spec:
      containers:
      - name: job
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
```

### 2. ttlSecondsAfterFinished 설정

```yaml
spec:
  ttlSecondsAfterFinished: 86400  # 24시간 후 자동 삭제
```

### 3. activeDeadlineSeconds 설정

```yaml
spec:
  activeDeadlineSeconds: 3600  # 최대 1시간 실행
```

### 4. 적절한 backoffLimit

```yaml
spec:
  backoffLimit: 3  # 3번 실패하면 중단
```

### 5. 멱등성 보장

Job은 재시도될 수 있으므로 여러 번 실행해도 안전해야 합니다:

```bash
# ✅ 멱등성 있음
CREATE TABLE IF NOT EXISTS users ...
INSERT INTO users ... ON DUPLICATE KEY UPDATE ...

# ❌ 멱등성 없음
CREATE TABLE users ...
INSERT INTO users ...
```

### 6. 로깅 및 에러 처리

```yaml
command:
- sh
- -c
- |
  set -e  # 에러 발생 시 즉시 종료
  
  echo "Starting job..."
  
  # 작업 수행
  if ! process_data; then
    echo "ERROR: Data processing failed"
    exit 1
  fi
  
  echo "Job completed successfully"
```

### 7. CronJob 타임존 설정

Kubernetes 1.25+에서 지원:

```yaml
spec:
  schedule: "0 9 * * *"
  timeZone: "Asia/Seoul"  # 한국 시간 기준
```

## 실습 과제

1. **기본 Job 실습**
   - 10개의 Pod를 병렬로 실행하는 Job 생성
   - 각 Pod는 간단한 계산 수행
   - 완료 후 로그 확인

2. **재시도 메커니즘 테스트**
   - 의도적으로 실패하는 Job 생성
   - backoffLimit 테스트
   - restartPolicy 차이 확인

3. **CronJob 구성**
   - 5분마다 실행되는 CronJob 생성
   - 히스토리 관리 확인
   - 수동 Job 실행 테스트

4. **백업 시뮬레이션**
   - 데이터 백업을 시뮬레이션하는 CronJob
   - PVC에 백업 파일 저장
   - 백업 파일 확인

## 참고 자료

- [Kubernetes Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [Kubernetes CronJobs](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
- [Cron 표현식 생성기](https://crontab.guru/)
- [Job 패턴](https://kubernetes.io/docs/concepts/workloads/controllers/job/#job-patterns)
