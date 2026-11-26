# ERP 로컬 인프라

담당 서비스 하나만 개발할 때는 해당 저장소의 README를 따라가세요. 프론트와 백엔드를 Gateway로 연결할 때 이 저장소를 사용합니다.

## Gateway 실행

같은 PC에서 담당 서비스를 먼저 실행한 뒤, 이 저장소에서 Gateway를 켜세요.

```sh
docker compose up -d --build gateway
```

[Gateway 상태 확인](http://localhost:8080/actuator/health)에서 `UP`을 확인하세요. 종료할 때는 `docker compose down`을 사용합니다.

## 새 API 연결

1. 도메인 담당자가 서비스 포트와 API 경로, 확인할 요청 한 개를 인프라 담당자에게 공유합니다.
2. 인프라 담당자가 [Gateway 라우트](api-gateway/src/main/resources/application.yml)와 [Compose의 서비스 주소](compose.yaml)를 등록합니다. PC에서 실행한 서비스 주소는 `http://host.docker.internal:<서비스 포트>`입니다.
3. Gateway를 다시 빌드하고 같은 요청을 서비스 포트와 Gateway 포트(`8080`)에 각각 보내 응답을 확인합니다.

## 통합용 로컬 DB

여러 서비스의 DB를 한 번에 준비할 때는 `docker compose up -d postgres`를 실행하세요. 접속 주소는 `localhost:5432`이며, 서비스별 DB와 계정은 [초기화 SQL](postgres/init.sql)에서 확인할 수 있습니다.

## Jenkins

도메인 저장소의 `main`과 `develop` 변경은 [공통 파이프라인](vars/erpService.groovy)에서 임시 PostgreSQL을 띄워 테스트하고 빌드합니다. Gateway 자체의 빌드와 상태 확인은 [인프라 파이프라인](Jenkinsfile)에서 실행합니다.

## Item 개발 서버 배포

개발 EC2에는 Docker Compose와 AWS CLI, SSM Agent가 필요합니다. Jenkins는 Item 이미지를 ECR에 올리고 SSM으로 배포 스크립트를 실행합니다.

1. EC2의 `/opt/erp`에 [Compose 파일](compose.dev.yaml)과 [배포 스크립트](deploy/deploy-item.sh)를 둡니다. EC2 역할에는 ECR 다운로드 권한이 필요합니다.
2. 같은 폴더의 `.env`에 `GATEWAY_IMAGE`, `ITEM_DB_URL`, `ITEM_DB_PASSWORD`를 설정합니다. DB 주소는 지속형 PostgreSQL의 `item_db`를 가리켜야 합니다. `registry.env`에는 셸 변수로 `AWS_REGION`, `ITEM_REPOSITORY`(태그 없는 ECR 주소)를 지정합니다. 두 파일은 서버 관리자만 읽고 쓰게 설정합니다.
3. Gateway 이미지를 서버에 준비하고 해당 폴더에서 `ITEM_IMAGE=bootstrap docker compose -f compose.dev.yaml up -d gateway`로 Gateway를 시작합니다. 기본 접속 주소는 서버 내부의 `127.0.0.1:8080`입니다. 팀 접근은 사내망 또는 승인된 터널을 사용합니다.
4. Jenkins에 `AWS_REGION`, `DEV_ITEM_REPOSITORY`, `DEV_INSTANCE_ID`를 등록합니다. Jenkins 역할에는 해당 이미지 업로드 및 대상 EC2에 대한 SSM 문서 `ERP-DeployItemDev` 실행·결과 조회 권한이 필요합니다. 이후 main 빌드가 성공하면 Item을 교체하고 DB를 포함한 상태를 확인합니다. 실패 시 직전 실행 이미지를 다시 시작합니다.

마지막 성공 이미지로 전체 구성을 다시 실행할 때는 `docker compose --env-file .env --env-file deployed.env -f compose.dev.yaml up -d`를 사용합니다.
