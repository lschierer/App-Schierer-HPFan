#!/bin/bash -x
set -eo pipefail

# Initialize mise environment
eval "$(mise activate bash)"

AWS_REGION='us-east-2';
AWS_ACCOUNT_ID='699040795025';
AWS_PROFILE='personal';

# pnpm requires that the lock file and the package.json be in sync, ensure that by running pnpm i
pnpm i

GIT_COMMIT=$(git rev-parse HEAD)
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Note: config.yml is not used - app reads share/conf/$mode.yml instead


# Create ECR repository (if it doesn't exist)
if aws --profile personal --region ${AWS_REGION} ecr describe-repositories | jq '.repositories.[].repositoryName' | grep -q hpfan ; then
  echo "repository already exists, not attempting creation."
else
  aws --profile ${AWS_PROFILE} --region ${AWS_REGION} ecr create-repository --repository-name hpfan
fi

# Get ECR login credentials and login
aws --profile ${AWS_PROFILE} --region ${AWS_REGION} ecr get-login-password | podman login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com || exit 1;

DEV=false
PROD=false

OPTSTRING=":dp"

while getopts "${OPTSTRING}" opt; do
  case ${opt} in
    d)
      DEV=true
      gsed -i -E 's/localDev/staging/' share/conf/test.yml
      ;;
    p)
      PROD=true
      gsed -i -E 's/localDev/production/' share/conf/production.yml
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

if ( ! $DEV  ) && ( ! $PROD ) ; then
  gsed -i -E 's/stage: .*$/stage: localDev/' share/conf/development.yml
fi
if ( $DEV  ) ; then
  gsed -i -E 's/stage: .*$/stage: localDev/' share/conf/test.yml
fi
if ( $PROD  ) ; then
  gsed -i -E 's/stage: .*$/stage: localDev/' share/conf/production.yml
fi


if ( ! $DEV  ) && ( ! $PROD ) ; then
  echo "local testing only, exiting without looking for cluster."
  podman build --platform linux/arm64 -t hpfan:latest ./
  exit 0;
else
  podman build --platform linux/arm64 -t hpfan:latest ./
  # Tag and push the image
  podman tag hpfan:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/hpfan:latest
  podman push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/hpfan:latest
fi


# Get all cluster ARNs
CLUSTERS=$(aws --profile personal --region us-east-2 ecs list-clusters | jq -r '.clusterArns[]' | grep HPFan)

# Loop through each cluster
for CLUSTER in $CLUSTERS; do
  # For dev environments
  if $DEV && echo "$CLUSTER" | grep -q -- '-dev-'; then
    echo "Processing dev cluster: $CLUSTER"

    # Get the first service in the cluster
    SERVICE=$(aws --profile personal --region us-east-2 ecs list-services --cluster "$CLUSTER" | jq -r '.serviceArns[0]')

    if [ -n "$SERVICE" ]; then
      echo "Forcing new deployment for service: $SERVICE"
      aws --profile personal --region us-east-2 ecs update-service \
        --no-cli-pager \
        --cluster "$CLUSTER" \
        --service "$SERVICE" \
        --force-new-deployment
    else
      echo "No services found in cluster: $CLUSTER"
    fi
  fi

  # For prod environments
  if $PROD && echo "$CLUSTER" | grep -q -- '-prod-'; then
    echo "Processing prod cluster: $CLUSTER"
    podman tag hpfan:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/hpfan:stable
    podman push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/hpfan:stable

    # Get the first service in the cluster
    SERVICE=$(aws --profile personal --region us-east-2 ecs list-services --cluster "$CLUSTER" | jq -r '.serviceArns[0]')

    if [ -n "$SERVICE" ]; then
      echo "Forcing new deployment for service: $SERVICE"
      aws --profile personal --region us-east-2 ecs update-service \
        --no-cli-pager \
        --cluster "$CLUSTER" \
        --service "$SERVICE" \
        --force-new-deployment
    else
      echo "No services found in cluster: $CLUSTER"
    fi
  fi
done
