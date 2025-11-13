# Spring Boot EC2 CI/CD Demo

GitHub → CodePipeline → CodeBuild → CodeDeploy → EC2(in-place) 데모.
배포 후 웹 페이지(http://<EC2_IP>:8080)에서 커밋 해시와 빌드 시간이 즉시 바뀝니다.

## Quick Start
1) EC2 보안그룹에 8080 오픈, CodeDeploy Agent 설치/실행
2) CodeDeploy 앱/배포그룹(EC2 태그 기반) 생성
3) CodePipeline(Source=GitHub, Build=CodeBuild, Deploy=CodeDeploy) 구성
4) GitHub에 커밋/푸시 → 파이프라인 완료 후 접속: http://<EC2_PUBLIC_IP>:8080
