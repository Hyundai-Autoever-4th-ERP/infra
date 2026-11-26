#!/bin/sh
set -eu

: "${AWS_REGION:?}" "${ECR_REPOSITORY_URI:?}" "${KUBE_CONTEXT:?}" "${KUBE_NAMESPACE:?}"
: "${LOCAL_IMAGE:?}" "${GIT_COMMIT:?}" "${BUILD_NUMBER:?}" "${DEPLOYMENT_NAME:?}" "${CONTAINER_NAME:?}"
registry=${ECR_REPOSITORY_URI%%/*}
repository=${ECR_REPOSITORY_URI#*/}
tag="$GIT_COMMIT-$BUILD_NUMBER"
target="$ECR_REPOSITORY_URI:$tag"

# 인증 정보는 이번 빌드의 임시 디렉터리에만 저장한다.
DOCKER_CONFIG=$(mktemp -d)
export DOCKER_CONFIG
trap 'rm -rf "$DOCKER_CONFIG"; docker image rm "$target" >/dev/null 2>&1 || true' EXIT

aws ecr get-login-password --region "$AWS_REGION" |
    docker login --username AWS --password-stdin "$registry"
docker tag "$LOCAL_IMAGE" "$target"
docker push "$target"
digest=$(aws ecr describe-images --region "$AWS_REGION" --repository-name "$repository" \
    --image-ids imageTag="$tag" --query 'imageDetails[0].imageDigest' --output text)
case "$digest" in
    sha256:*) ;;
    *) echo "ECR 이미지 digest를 확인할 수 없습니다." >&2; exit 1 ;;
esac

kubectl --context "$KUBE_CONTEXT" -n "$KUBE_NAMESPACE" set image \
    "deployment/$DEPLOYMENT_NAME" "$CONTAINER_NAME=$ECR_REPOSITORY_URI@$digest"
kubectl --context "$KUBE_CONTEXT" -n "$KUBE_NAMESPACE" rollout status "deployment/$DEPLOYMENT_NAME" --timeout=180s
