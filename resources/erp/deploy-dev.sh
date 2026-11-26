#!/bin/sh
set -eu
: "${AWS_REGION:?}" "${DEV_ECR_REGISTRY:?}" "${DEV_INSTANCE_ID:?}"
aws_cli() {
    if command -v aws >/dev/null 2>&1; then aws "$@"; else
        docker run --rm --network host public.ecr.aws/aws-cli/aws-cli:2.31.0 "$@"
    fi
}
case "${ERP_SERVICE:?}" in
    erp-auth|erp-item|erp-inventory|erp-procurement|erp-sales|erp-notification) ;;
    *) echo "Unknown service: $ERP_SERVICE" >&2; exit 1 ;;
esac
repository="$DEV_ECR_REGISTRY/$ERP_SERVICE"
tag="$(git rev-parse HEAD)-${BUILD_NUMBER:?}"
image="$repository:$tag"
export DOCKER_CONFIG
DOCKER_CONFIG=$(mktemp -d)
trap 'rm -rf "$DOCKER_CONFIG"; docker image rm "$image" >/dev/null 2>&1 || true' EXIT
aws_cli ecr get-login-password --region "$AWS_REGION" > "$DOCKER_CONFIG/password"
docker login --username AWS --password-stdin "${repository%%/*}" < "$DOCKER_CONFIG/password"
rm "$DOCKER_CONFIG/password"
docker build -t "$image" .
docker push "$image"
digest=$(aws_cli ecr describe-images --region "$AWS_REGION" --repository-name "${repository#*/}" --image-ids "imageTag=$tag" --query 'imageDetails[0].imageDigest' --output text)
printf '%s\n' "$digest" | grep -Eq '^sha256:[0-9a-f]{64}$'
id=$(aws_cli ssm send-command --region "$AWS_REGION" --instance-ids "$DEV_INSTANCE_ID" --document-name ERP-DeployServiceDev --parameters "service=$ERP_SERVICE,digest=$digest" --query 'Command.CommandId' --output text)
for attempt in $(seq 1 90); do
    status=$(aws_cli ssm list-command-invocations --region "$AWS_REGION" --command-id "$id" --instance-id "$DEV_INSTANCE_ID" --query 'CommandInvocations[0].Status' --output text)
    case "$status" in
        Success) exit 0 ;;
        None|Pending|InProgress|Delayed) sleep 5 ;;
        *) echo "SSM $id: $status" >&2; exit 1 ;;
    esac
done
echo "SSM $id timed out" >&2
exit 1
