# AWS CI/CD Pipeline 구축 가이드

GitHub → CodePipeline → CodeBuild → CodeDeploy → EC2 자동 배포 파이프라인 구축 가이드

---

## 목차
1. [사전 준비](#1-사전-준비)
2. [EC2 인스턴스 설정](#2-ec2-인스턴스-설정)
3. [IAM 역할 생성](#3-iam-역할-생성)
4. [CodeDeploy 애플리케이션 및 배포 그룹 생성](#4-codedeploy-애플리케이션-및-배포-그룹-생성)
5. [CodeBuild 프로젝트 생성](#5-codebuild-프로젝트-생성)
6. [CodePipeline 생성](#6-codepipeline-생성)
7. [배포 테스트](#7-배포-테스트)
8. [문제 해결](#8-문제-해결)

---

## 1. 사전 준비

### 1.1 필요한 파일 확인
다음 파일들이 프로젝트에 포함되어 있는지 확인:
- `buildspec.yml` - CodeBuild 빌드 스펙
- `appspec.yml` - CodeDeploy 배포 스펙
- `scripts/` - 배포 라이프사이클 훅 스크립트
  - `before_install.sh`
  - `stop_app.sh`
  - `start_app.sh`
  - `validate.sh`
- `systemd/demo.service` - systemd 서비스 정의
- `app/pom.xml` - Maven 프로젝트 설정

### 1.2 GitHub 리포지토리 준비
- GitHub 리포지토리에 프로젝트 코드 푸시
- 리포지토리 URL 확인 (예: `https://github.com/사용자명/리포지토리명`)

---

## 2. EC2 인스턴스 설정

### 2.1 EC2 인스턴스 생성
1. **AWS Console** → **EC2** → **인스턴스 시작**
2. 설정:
   - **AMI**: Amazon Linux 2023 또는 Amazon Linux 2
   - **인스턴스 유형**: t2.micro (프리티어) 또는 t3.small
   - **키 페어**: 새로 생성 또는 기존 키 페어 선택
   - **보안 그룹**:
     - SSH (22) - 내 IP
     - Custom TCP (8080) - 0.0.0.0/0 (또는 특정 IP)

3. **IAM 역할 연결** (인스턴스 프로필):
   - 나중에 생성할 `EC2-CodeDeploy-Role` 연결 (3.1 참조)

4. **태그 추가** (중요!):
   - Key: `Name`, Value: `demo-app-server`
   - Key: `Environment`, Value: `dev`
   - 또는 원하는 태그 (CodeDeploy 배포 그룹에서 사용)

### 2.2 CodeDeploy Agent 설치

SSH로 EC2 접속 후:

```bash
# Amazon Linux 2023 / Amazon Linux 2
sudo yum update -y

# Ruby 설치 (CodeDeploy Agent 필요)
sudo yum install ruby wget -y

# CodeDeploy Agent 설치 스크립트 다운로드 및 실행
cd /home/ec2-user
wget https://aws-codedeploy-ap-northeast-2.s3.ap-northeast-2.amazonaws.com/latest/install
chmod +x ./install
sudo ./install auto

# Agent 상태 확인
sudo systemctl status codedeploy-agent
```

**다른 리전의 경우** `ap-northeast-2`를 해당 리전으로 변경
- 도쿄: `ap-northeast-1`
- 버지니아: `us-east-1`
- 오하이오: `us-east-2`

### 2.3 Java 17 설치 (선택)

```bash
# Amazon Corretto 17 설치
sudo yum install -y java-17-amazon-corretto-headless

# 버전 확인
java -version
```

> 참고: `before_install.sh` 스크립트가 Java를 자동 설치하므로 선택 사항입니다.

---

## 3. IAM 역할 생성

### 3.1 EC2용 IAM 역할 생성

1. **AWS Console** → **IAM** → **역할** → **역할 만들기**
2. **신뢰할 수 있는 엔터티 유형**: AWS 서비스
3. **사용 사례**: EC2
4. **권한 정책 연결**:
   - `AmazonS3ReadOnlyAccess` (CodeDeploy가 S3에서 아티팩트 다운로드)
5. **역할 이름**: `EC2-CodeDeploy-Role`
6. **생성 후**: EC2 인스턴스에 역할 연결
   - EC2 콘솔 → 인스턴스 선택 → 작업 → 보안 → IAM 역할 수정

### 3.2 CodeDeploy용 IAM 역할 생성

1. **역할 만들기**
2. **신뢰할 수 있는 엔터티 유형**: AWS 서비스
3. **사용 사례**: CodeDeploy
4. **권한 정책 자동 연결됨**: `AWSCodeDeployRole`
5. **역할 이름**: `CodeDeploy-Service-Role`

### 3.3 CodeBuild용 IAM 역할 생성

CodeBuild 프로젝트 생성 시 자동 생성되거나, 수동으로 생성:

1. **역할 만들기**
2. **신뢰할 수 있는 엔터티 유형**: AWS 서비스
3. **사용 사례**: CodeBuild
4. **권한 정책**:
   - `AWSCodeBuildDeveloperAccess`
   - S3 접근 권한 (아티팩트 업로드)
   - CloudWatch Logs 권한
5. **역할 이름**: `CodeBuild-Service-Role`

### 3.4 CodePipeline용 IAM 역할 생성

CodePipeline 생성 시 자동 생성되거나, 수동으로 생성:

1. **역할 만들기**
2. **신뢰할 수 있는 엔터티 유형**: AWS 서비스
3. **사용 사례**: CodePipeline
4. **권한 정책**: 자동으로 연결됨
5. **역할 이름**: `CodePipeline-Service-Role`

---

## 4. CodeDeploy 애플리케이션 및 배포 그룹 생성

### 4.1 CodeDeploy 애플리케이션 생성

1. **AWS Console** → **CodeDeploy** → **애플리케이션** → **애플리케이션 생성**
2. **애플리케이션 이름**: `demo-app`
3. **컴퓨팅 플랫폼**: EC2/온프레미스
4. **생성**

### 4.2 배포 그룹 생성

1. 생성한 애플리케이션에서 **배포 그룹 생성**
2. 설정:
   - **배포 그룹 이름**: `demo-app-deployment-group`
   - **서비스 역할**: `CodeDeploy-Service-Role` (3.2에서 생성)
   - **배포 유형**: 현재 위치
   - **환경 구성**: Amazon EC2 인스턴스
   - **태그 그룹**:
     - Key: `Environment`, Value: `dev` (또는 2.1에서 설정한 태그)
   - **배포 설정**: `CodeDeployDefault.AllAtOnce` (한 번에 모두 배포)
   - **로드 밸런서**: 비활성화 (선택 사항)
3. **배포 그룹 생성**

### 4.3 확인

- 배포 그룹에서 **대상** 탭 확인
- EC2 인스턴스가 1개 이상 표시되어야 함
- 표시되지 않으면:
  - EC2 태그 확인
  - CodeDeploy Agent 실행 상태 확인: `sudo systemctl status codedeploy-agent`

---

## 5. CodeBuild 프로젝트 생성

### 5.1 CodeBuild 프로젝트 생성

1. **AWS Console** → **CodeBuild** → **빌드 프로젝트** → **빌드 프로젝트 생성**
2. **프로젝트 구성**:
   - **프로젝트 이름**: `demo-app-build`

3. **소스**:
   - **소스 공급자**: GitHub
   - **리포지토리**: 리포지토리 연결 (OAuth 또는 개인 액세스 토큰)
   - **리포지토리 URL**: GitHub 리포지토리 선택
   - **소스 버전**: `refs/heads/main` (또는 사용하는 브랜치)

4. **환경**:
   - **환경 이미지**: 관리형 이미지
   - **운영 체제**: Amazon Linux 2
   - **런타임**: Standard
   - **이미지**: `aws/codebuild/amazonlinux2-x86_64-standard:5.0` (최신)
   - **이미지 버전**: 항상 최신 이미지 사용
   - **환경 유형**: Linux
   - **서비스 역할**: 새 서비스 역할 (자동 생성) 또는 기존 역할
   - **권한 있음**: 체크 (Docker 이미지 빌드가 필요한 경우)

5. **Buildspec**:
   - **빌드 사양**: buildspec 파일 사용
   - **Buildspec 이름**: `buildspec.yml` (기본값, 프로젝트 루트에 위치)

6. **아티팩트**:
   - **유형**: Amazon S3
   - **버킷 이름**: 새 버킷 생성 또는 기존 버킷 선택
   - **이름**: `demo-app-artifacts` (또는 원하는 이름)
   - **경로**: (비워둠)
   - **네임스페이스 유형**: 없음
   - **아티팩트 패키징**: Zip

7. **로그**:
   - **CloudWatch 로그**: 활성화 (선택)
   - **S3 로그**: 비활성화 (선택)

8. **빌드 프로젝트 생성**

### 5.2 빌드 테스트 (선택)

- **빌드 시작** 버튼 클릭
- 빌드 로그 확인
- 성공하면 S3 버킷에 아티팩트 생성 확인

---

## 6. CodePipeline 생성

### 6.1 파이프라인 생성

1. **AWS Console** → **CodePipeline** → **파이프라인** → **파이프라인 생성**
2. **파이프라인 설정**:
   - **파이프라인 이름**: `demo-app-pipeline`
   - **서비스 역할**: 새 서비스 역할 (자동 생성)
   - **역할 이름**: `AWSCodePipelineServiceRole-ap-northeast-2-demo-app-pipeline` (자동)
   - **아티팩트 저장소**: 기본 위치 (S3 버킷 자동 생성)
   - **다음**

### 6.2 소스 스테이지 추가

1. **소스 공급자**: GitHub (버전 2) 권장
   - **연결**: GitHub Apps 연결 생성 또는 기존 연결 선택
   - 처음 연결 시:
     - **GitHub에 연결** 클릭
     - **연결 이름**: `github-connection`
     - GitHub 앱 설치 및 권한 부여
   - **리포지토리 이름**: 리포지토리 선택
   - **브랜치 이름**: `main` (또는 사용하는 브랜치)
   - **출력 아티팩트 형식**: CodePipeline 기본값
2. **다음**

### 6.3 빌드 스테이지 추가

1. **빌드 공급자**: AWS CodeBuild
2. **리전**: 현재 리전
3. **프로젝트 이름**: `demo-app-build` (5.1에서 생성)
4. **빌드 유형**: 단일 빌드
5. **다음**

### 6.4 배포 스테이지 추가

1. **배포 공급자**: AWS CodeDeploy
2. **리전**: 현재 리전
3. **애플리케이션 이름**: `demo-app` (4.1에서 생성)
4. **배포 그룹**: `demo-app-deployment-group` (4.2에서 생성)
5. **다음**

### 6.5 검토 및 생성

1. 모든 설정 검토
2. **파이프라인 생성**

### 6.6 자동 실행

- 파이프라인 생성 즉시 자동으로 실행됨
- 각 스테이지 진행 상황 모니터링:
  - **Source**: GitHub에서 코드 가져오기
  - **Build**: CodeBuild로 빌드 및 아티팩트 생성
  - **Deploy**: CodeDeploy로 EC2에 배포

---

## 7. 배포 테스트

### 7.1 파이프라인 실행 확인

1. CodePipeline 콘솔에서 각 스테이지 상태 확인
2. **Source** → **Build** → **Deploy** 순서로 진행
3. 모든 스테이지가 **성공**으로 표시되어야 함

### 7.2 EC2 인스턴스 확인

SSH로 EC2 접속:

```bash
# systemd 서비스 상태 확인
sudo systemctl status demo.service

# 서비스 로그 확인
sudo journalctl -u demo.service -n 50 --no-pager

# Java 프로세스 확인
ps aux | grep java

# 배포된 파일 확인
ls -la /home/ec2-user/app/
```

### 7.3 애플리케이션 테스트

브라우저 또는 curl로 접속:

```bash
# 로컬에서 테스트
curl http://<EC2_PUBLIC_IP>:8080/api/build

# 브라우저
http://<EC2_PUBLIC_IP>:8080/api/build
```

**예상 응답**:
```json
{
  "commit": "0517f0d...",
  "builtAt": "2025-01-13T12:34:56Z"
}
```

### 7.4 자동 배포 테스트

1. 로컬에서 코드 수정 (예: `BuildController.java`)
2. GitHub에 커밋 및 푸시:
   ```bash
   git add .
   git commit -m "Test auto deployment"
   git push origin main
   ```
3. CodePipeline에서 자동 실행 확인
4. 배포 완료 후 애플리케이션 접속하여 변경사항 확인

---

## 8. 문제 해결

### 8.1 CodeDeploy Agent 오류

**증상**: 배포 그룹에 EC2 인스턴스가 표시되지 않음

**해결**:
```bash
# Agent 상태 확인
sudo systemctl status codedeploy-agent

# Agent 재시작
sudo systemctl restart codedeploy-agent

# Agent 로그 확인
sudo tail -f /var/log/aws/codedeploy-agent/codedeploy-agent.log
```

### 8.2 배포 실패

**증상**: CodeDeploy 배포 단계에서 실패

**해결**:
1. CodeDeploy 콘솔 → 배포 → 실패한 배포 선택
2. **이벤트** 탭에서 실패 단계 확인
3. EC2에서 스크립트 로그 확인:
   ```bash
   # CodeDeploy 로그
   sudo tail -f /opt/codedeploy-agent/deployment-root/deployment-logs/codedeploy-agent-deployments.log

   # 애플리케이션 로그
   sudo journalctl -u demo.service -n 100 --no-pager
   ```

### 8.3 systemd 서비스 시작 실패

**증상**: `validate.sh`에서 서비스가 active 상태가 아님

**해결**:
```bash
# 서비스 상태 상세 확인
sudo systemctl status demo.service -l

# 서비스 로그 확인
sudo journalctl -u demo.service -n 100 --no-pager

# 수동으로 서비스 시작
sudo systemctl restart demo.service
```

**일반적인 원인**:
- Java가 설치되지 않음
- JAR 파일 경로 오류
- 포트 8080이 이미 사용 중
- systemd 서비스 파일의 메인 클래스 이름 불일치

### 8.4 빌드 실패

**증상**: CodeBuild 단계에서 실패

**해결**:
1. CodeBuild 콘솔 → 빌드 프로젝트 → 빌드 기록 → 실패한 빌드 선택
2. **빌드 로그** 탭에서 오류 메시지 확인
3. 일반적인 원인:
   - `buildspec.yml` 문법 오류
   - Maven 빌드 오류 (의존성, 컴파일 오류)
   - 빌드 환경 권한 부족

### 8.5 GitHub 연결 오류

**증상**: 소스 스테이지에서 GitHub 연결 실패

**해결**:
1. CodePipeline 콘솔 → 설정 → 연결
2. GitHub 연결 상태 확인
3. 연결이 "사용 가능" 상태가 아니면:
   - 연결 삭제 후 재생성
   - GitHub에서 앱 권한 재확인

### 8.6 포트 8080 접근 불가

**증상**: 브라우저에서 애플리케이션 접근 불가

**해결**:
1. EC2 보안 그룹 확인:
   - 인바운드 규칙에 포트 8080 추가
   - 소스: 0.0.0.0/0 (또는 특정 IP)
2. 애플리케이션 실행 상태 확인:
   ```bash
   sudo systemctl status demo.service
   sudo netstat -tlnp | grep 8080
   ```

### 8.7 IAM 권한 오류

**증상**: "Access Denied" 또는 권한 관련 오류

**해결**:
- EC2 역할: `AmazonS3ReadOnlyAccess` 권한 확인
- CodeDeploy 역할: `AWSCodeDeployRole` 권한 확인
- CodeBuild 역할: S3, CloudWatch Logs 권한 확인
- CodePipeline 역할: CodeBuild, CodeDeploy, S3 권한 확인

---

## 부록

### A. 유용한 AWS CLI 명령어

```bash
# CodeDeploy 배포 목록
aws deploy list-deployments --application-name demo-app

# 특정 배포 상태 확인
aws deploy get-deployment --deployment-id <deployment-id>

# EC2 인스턴스 정보
aws ec2 describe-instances --filters "Name=tag:Environment,Values=dev"

# CodePipeline 실행
aws codepipeline start-pipeline-execution --name demo-app-pipeline
```

### B. buildspec.yml 주요 단계

1. **install**: Maven 설치
2. **pre_build**: pom.xml 존재 확인
3. **build**: `mvn clean package` 실행
4. **post_build**: 아티팩트 구조 생성, build.json 생성

### C. appspec.yml 라이프사이클 훅

1. **BeforeInstall** → `before_install.sh`: 환경 준비
2. **ApplicationStop** → `stop_app.sh`: 기존 서비스 중지
3. **Install**: 파일 배포 (자동)
4. **ApplicationStart** → `start_app.sh`: 서비스 시작
5. **ValidateService** → `validate.sh`: 배포 검증

### D. 참고 자료

- [AWS CodePipeline 문서](https://docs.aws.amazon.com/codepipeline/)
- [AWS CodeBuild 문서](https://docs.aws.amazon.com/codebuild/)
- [AWS CodeDeploy 문서](https://docs.aws.amazon.com/codedeploy/)
- [CodeDeploy Agent 설치](https://docs.aws.amazon.com/codedeploy/latest/userguide/codedeploy-agent-operations-install.html)

---

## 요약

1. **EC2 인스턴스 생성** → 태그 추가 → CodeDeploy Agent 설치
2. **IAM 역할 생성** → EC2, CodeDeploy, CodeBuild, CodePipeline용 역할
3. **CodeDeploy 설정** → 애플리케이션 및 배포 그룹 생성
4. **CodeBuild 설정** → 빌드 프로젝트 생성
5. **CodePipeline 생성** → Source (GitHub) → Build → Deploy 연결
6. **테스트** → GitHub에 푸시 → 자동 배포 확인

이제 코드를 GitHub에 푸시할 때마다 자동으로 빌드 및 배포가 진행됩니다!