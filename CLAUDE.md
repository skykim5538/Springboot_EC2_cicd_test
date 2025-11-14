# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## 프로젝트 개요 (한글)

이 프로젝트는 AWS CI/CD 파이프라인 통합을 보여주는 Spring Boot 3.3.1 애플리케이션입니다:
- **파이프라인 흐름**: GitHub → CodePipeline → CodeBuild → CodeDeploy → EC2 (in-place 배포)
- **목적**: 배포 후 http://<EC2_IP>:8080 에서 커밋 해시와 빌드 시간이 즉시 표시되는 자동화된 배포 데모
- **기술 스택**: Java 17, Spring Boot 3.3.1, Maven, AWS CodeDeploy, systemd

## 빌드 명령어

```bash
# 애플리케이션 빌드 (프로젝트 루트에서)
mvn -B -DskipTests -f app/pom.xml clean package

# 로컬 실행
cd app
mvn spring-boot:run

# 특정 프로파일로 실행
mvn spring-boot:run -Dspring-boot.run.profiles=local
```

빌드된 JAR 파일 위치: `app/target/springboot-ec2-cicd-demo-0.0.1-SNAPSHOT.jar`

## 프로젝트 구조

```
app/
├── pom.xml                          # Maven 설정 (Java 17, Spring Boot 3.3.1)
├── src/main/java/demo/
│   ├── DemoApplication.java         # Spring Boot 메인 애플리케이션 진입점
│   └── BuildController.java         # 빌드 메타데이터를 반환하는 /api/build REST 엔드포인트
└── src/main/resources/
    └── application.yml              # Spring 프로파일: local (H2 인메모리), prod (H2 파일 기반)

buildspec.yml                        # AWS CodeBuild 빌드 스펙
appspec.yml                          # AWS CodeDeploy 배포 스펙

scripts/                             # CodeDeploy 라이프사이클 훅 스크립트
├── before_install.sh                # 환경 준비, Java 17 설치
├── stop_app.sh                      # 배포 전 systemd 서비스 중지
├── start_app.sh                     # systemd 서비스 파일 복사 및 시작
└── validate.sh                      # 배포 성공 검증

systemd/
└── demo.service                     # 앱을 위한 systemd 서비스 정의
```

## 아키텍처

### 애플리케이션 레이어
- **메인 애플리케이션**: `DemoApplication.java`는 표준 Spring Boot 진입점
- **빌드 정보 엔드포인트**: `BuildController.java`는 `/api/build`를 노출하며 `/opt/demo/build.json`을 읽어 커밋 해시와 빌드 타임스탬프 제공 (CodeBuild에서 생성)

### 배포 아키텍처
1. **CodeBuild 단계** (buildspec.yml):
   - Maven이 없으면 설치
   - `mvn -B -DskipTests -f app/pom.xml clean package`로 JAR 빌드
   - app.jar, scripts, systemd 파일, build.json을 포함한 아티팩트 구조 생성
   - build.json 내용: `{"commit":"<hash>","builtAt":"<timestamp>"}`

2. **CodeDeploy 단계** (appspec.yml):
   - **BeforeInstall**: `/home/ec2-user/app` 디렉토리 생성, Java 17 설치
   - **ApplicationStop**: 기존 systemd 서비스 중지
   - **배포되는 파일들**:
     - `app.jar` → `/home/ec2-user/app/`
     - 스크립트 → `/home/ec2-user/scripts/`
     - systemd 서비스 → `/home/ec2-user/systemd/`
   - **ApplicationStart**: systemd 서비스 파일을 `/etc/systemd/system/`에 복사, 서비스 활성화 및 시작
   - **ValidateService**: systemd 서비스 상태 및 로그 확인

3. **런타임**:
   - 애플리케이션은 `ec2-user` 사용자로 systemd 서비스 `demo.service`로 실행
   - 8080 포트에서 리스닝
   - 실패 시 자동 재시작 (RestartSec=5)

### 설정 프로파일
- **local**: H2 인메모리 데이터베이스, `/h2-console`에서 콘솔 활성화, SQL 로깅 활성화
- **prod**: `./data/shoppingmall`에 H2 파일 기반 데이터베이스, 콘솔 비활성화, `/home/ec2-user/logs/application.log`에 로그 저장

## 주요 참고사항

- 애플리케이션은 `/opt/demo/build.json`에서 빌드 메타데이터를 읽으려 하지만, buildspec은 `artifact/app/public/build.json`에 작성합니다. 배포 설정에서 이 경로 매핑을 확인하세요.
- EC2 보안 그룹에서 8080 포트가 열려 있어야 합니다
- EC2 인스턴스에 CodeDeploy Agent가 설치되어 실행 중이어야 합니다
- CodeDeploy 배포 그룹은 EC2 태그를 사용하여 대상을 선택해야 합니다
- systemd 서비스 파일이 실제 패키지 구조와 일치해야 하는 메인 클래스 참조를 포함합니다 (현재 `demo.SpringbootEc2CicdDemoApplication`을 참조하지만 실제 클래스는 `demo.DemoApplication`)

---

## Project Overview

This is a Spring Boot 3.3.1 application demonstrating AWS CI/CD pipeline integration:
- **Pipeline Flow**: GitHub → CodePipeline → CodeBuild → CodeDeploy → EC2 (in-place deployment)
- **Purpose**: Demonstrates automated deployment where commit hash and build time are immediately visible at http://<EC2_IP>:8080 after deployment
- **Technology Stack**: Java 17, Spring Boot 3.3.1, Maven, AWS CodeDeploy, systemd

## Build Commands

```bash
# Build the application (from project root)
mvn -B -DskipTests -f app/pom.xml clean package

# Run locally
cd app
mvn spring-boot:run

# Run with specific profile
mvn spring-boot:run -Dspring-boot.run.profiles=local
```

The built JAR is located at `app/target/springboot-ec2-cicd-demo-0.0.1-SNAPSHOT.jar`

## Project Structure

```
app/
├── pom.xml                          # Maven configuration (Java 17, Spring Boot 3.3.1)
├── src/main/java/demo/
│   ├── DemoApplication.java         # Main Spring Boot application entry point
│   └── BuildController.java         # REST endpoint at /api/build returning build metadata
└── src/main/resources/
    └── application.yml              # Spring profiles: local (H2 in-memory), prod (H2 file-based)

buildspec.yml                        # AWS CodeBuild build specification
appspec.yml                          # AWS CodeDeploy deployment specification

scripts/                             # CodeDeploy lifecycle hook scripts
├── before_install.sh                # Prepares environment, installs Java 17
├── stop_app.sh                      # Stops systemd service before deployment
├── start_app.sh                     # Copies systemd service file, starts service
└── validate.sh                      # Validates deployment success

systemd/
└── demo.service                     # systemd service definition for the app
```

## Architecture

### Application Layer
- **Main Application**: `DemoApplication.java` is a standard Spring Boot entry point
- **Build Info Endpoint**: `BuildController.java` exposes `/api/build` which reads `/opt/demo/build.json` (populated during CodeBuild) containing commit hash and build timestamp

### Deployment Architecture
1. **CodeBuild Phase** (buildspec.yml):
   - Installs Maven if not present
   - Builds JAR with `mvn -B -DskipTests -f app/pom.xml clean package`
   - Creates artifact structure with app.jar, scripts, systemd files, and build.json
   - build.json contains: `{"commit":"<hash>","builtAt":"<timestamp>"}`

2. **CodeDeploy Phase** (appspec.yml):
   - **BeforeInstall**: Creates `/home/ec2-user/app` directory, installs Java 17
   - **ApplicationStop**: Stops existing systemd service
   - **Files Deployed**:
     - `app.jar` → `/home/ec2-user/app/`
     - Scripts → `/home/ec2-user/scripts/`
     - systemd service → `/home/ec2-user/systemd/`
   - **ApplicationStart**: Copies systemd service file to `/etc/systemd/system/`, enables and starts service
   - **ValidateService**: Checks systemd service status and logs

3. **Runtime**:
   - Application runs as systemd service `demo.service` under user `ec2-user`
   - Listens on port 8080
   - Auto-restarts on failure (RestartSec=5)

### Configuration Profiles
- **local**: H2 in-memory database, console enabled at `/h2-console`, SQL logging on
- **prod**: H2 file-based database at `./data/shoppingmall`, console disabled, logs to `/home/ec2-user/logs/application.log`

## Key Notes

- The application expects build metadata at `/opt/demo/build.json` but the buildspec writes it to `artifact/app/public/build.json`. Verify this path mapping in your deployment configuration.
- Port 8080 must be open in EC2 security group
- EC2 instance must have CodeDeploy Agent installed and running
- CodeDeploy deployment group should use EC2 tags for target selection
- systemd service file contains main class reference that should match the actual package structure (currently references `demo.SpringbootEc2CicdDemoApplication` but actual class is `demo.DemoApplication`)