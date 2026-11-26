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
