# ERP 로컬 인프라

## 실행

Docker를 켜고 ERP 상위 폴더에서 처음 한 번 클론한다. 비공개 저장소 접근 권한이 필요하다.

```sh
git clone https://github.com/Hyundai-Autoever-4th-ERP/infra.git
cd infra
```

이후에는 `infra` 폴더에서 필요한 명령을 실행한다.

**담당 서비스 개발 · DB만 실행**

```sh
docker compose up -d postgres
```

**프론트와 API 연동 · DB와 Gateway 실행**

```sh
docker compose up -d --build
```

[Gateway 상태 확인](http://localhost:8080/actuator/health)에서 `UP`이 보이면 Gateway가 실행 중이다. 종료할 때는 `docker compose down`을 사용한다.

## 백엔드 서비스를 Gateway에 연결하기

1. **도메인 담당자**는 서비스의 로컬 포트, Gateway에 연결할 API 경로, 확인할 요청 한 개(HTTP 메서드·경로·예상 응답)를 인프라 담당자한테 공유한다.
2. **인프라 담당자**는 [Gateway 설정](api-gateway/src/main/resources/application.yml)의 `routes`에 서비스와 경로를 등록한다. 서비스가 팀원 PC에서 실행된다면 [Compose 설정](compose.yaml)의 `gateway.environment`에 대상 주소를 `http://host.docker.internal:<서비스 포트>`로 지정한다.
3. **연결 확인**은 같은 PC에서 한다. 담당 서비스를 실행하고 `infra`에서 `docker compose up -d --build gateway`를 실행한 뒤, 같은 요청을 서비스 포트와 Gateway 포트(기본 `8080`)로 각각 보내 예상 응답이 오는지 확인한다.

## PostgreSQL 접속

로컬 접속 주소는 **localhost:5432**다. 아래에서 담당 서비스의 계정을 확인한다.

| 서비스 | 데이터베이스 | 사용자 | 로컬 비밀번호 |
| --- | --- | --- | --- |
| 인증 | `auth_db` | `auth_app` | `auth_local` |
| 품목 | `item_db` | `item_app` | `item_local` |
| 재고 | `inventory_db` | `inventory_app` | `inventory_local` |
| 구매 | `procurement_db` | `procurement_app` | `procurement_local` |
| 판매 | `sales_db` | `sales_app` | `sales_local` |
| 알림 | `noti_db` | `noti_app` | `noti_local` |

## Jenkins · 인프라 담당자

팀원은 로컬 개발에 Docker만 사용한다. Jenkins는 전용 서버에서 이 저장소의 [Jenkinsfile](Jenkinsfile)을 실행한다.

1. Jenkins에 Pipeline, Git, GitHub Branch Source 플러그인을 설치한다. Linux 빌드 에이전트에 `erp-docker` 라벨을 붙이고 Git, Docker Engine, Compose v2, curl을 준비한다. 에이전트에서 로컬 Docker 데몬에 접근할 수 있어야 한다.
2. **Multibranch Pipeline**을 만들고 GitHub 소스에 이 저장소와 읽기용 자격 증명을 등록한다. 브랜치 검색 대상은 `main`과 `develop`으로 제한하고 PR·포크 검색은 끈다. 주기적 스캔(예: 5분)을 설정하고 **Scan Multibranch Pipeline Now**로 시작한다.
3. 기본 빌드는 Gradle 검사와 Gateway 이미지 빌드 후 임시 컨테이너에서 `/actuator/health`를 확인한다. 로컬에서도 같은 검사를 실행할 수 있다.

```sh
docker build -f api-gateway/Dockerfile -t erp-gateway:check .
./ci/check-gateway.sh erp-gateway:check
```

**클라우드 시연 배포**는 로컬 통합 후 진행한다. 준비된 ECR 저장소와 Kubernetes의 `api-gateway` Deployment(컨테이너 이름도 `api-gateway`)를 사용한다. 에이전트에 AWS CLI와 kubectl을 설치하고, EC2 역할에 ECR 인증·업로드·이미지 조회 권한을 부여한다. kubeconfig에는 대상 Deployment 갱신·롤아웃 조회 권한이 필요하며, 클러스터는 해당 ECR 이미지를 받을 수 있어야 한다.

Jenkins 환경에 `AWS_REGION`, `ECR_REPOSITORY_URI`(태그 제외), `KUBE_CONTEXT`, `KUBE_NAMESPACE`를 등록한다. `main` 작업에서 **Build with Parameters → DEPLOY**를 선택하면 검사를 통과한 이미지를 ECR에 올리고, 해당 digest로 Gateway를 갱신한 뒤 롤아웃 결과를 확인한다.

### 도메인 저장소 연결

각 `erp-*` 저장소의 Jenkinsfile은 이 저장소의 공통 Pipeline(`vars/erpService.groovy`)을 호출한다.

1. 읽기 전용 GitHub App으로 `infra`와 도메인 저장소 6개에 접근한다. 공통 라이브러리 `erp-ci`는 `infra/main`을 사용한다.
2. 각 저장소의 Multibranch Pipeline은 `main`과 `develop`을 5분 간격으로 확인한다. 에이전트 1개가 빌드를 순차 처리한다.
3. 매 빌드는 전용 PostgreSQL 17에 서비스 계정으로 접속한다. 서비스에 Gradle Wrapper가 있으면 JDK 25 컨테이너에서 테스트와 빌드도 실행한다. 초기 저장소는 DB 연결까지만 검증한다.
4. 배포할 서비스는 루트에 독립 빌드 가능한 Dockerfile을 둔다. `ECR_REPOSITORY_URI`는 작업별로 해당 서비스의 ECR 주소를 지정한다. Kubernetes Deployment와 컨테이너 이름은 저장소 이름(예: `erp-item`)을 쓴다. 승인된 `main` 빌드에서 `DEPLOY`를 선택하면 위와 같은 방식으로 이미지를 배포한다. 배포 자격 증명은 보호된 main 작업에서만 쓸 수 있도록 Jenkins에서 접근을 제한하고 PR 빌드는 배포 에이전트에서 실행하지 않는다.
