#!/bin/bash
set -e

REGISTRY="192.168.31.229:5000"
IMAGE="backup_runner"
VERSION=$(git rev-parse --short=6 HEAD)

echo "Building and pushing amd64 image..."
docker buildx build --platform linux/amd64 \
  --build-arg MEGA_OS=Debian_12 \
  --build-arg MEGA_ARCHITECTURE=amd64 \
  -t ${REGISTRY}/${IMAGE}:${VERSION}-amd64 \
  --push .

echo "Building and pushing arm64 image..."
docker buildx build --platform linux/arm64 \
  --build-arg MEGA_OS=Raspbian_12 \
  --build-arg MEGA_ARCHITECTURE=armhf \
  -t ${REGISTRY}/${IMAGE}:${VERSION}-arm64 \
  --push .


echo " - Removing ${REGISTRY}/${IMAGE}:latest if it exists..."
if docker manifest inspect ${REGISTRY}/${IMAGE}:latest > /dev/null 2>&1; then
  docker manifest rm ${REGISTRY}/${IMAGE}:latest || true
else
  echo "   No existing manifest for latest found, skipping removal."
fi

echo "Creating manifest for ${VERSION}..."
docker manifest create --amend --insecure ${REGISTRY}/${IMAGE}:${VERSION} \
  ${REGISTRY}/${IMAGE}:${VERSION}-amd64 \
  ${REGISTRY}/${IMAGE}:${VERSION}-arm64

docker manifest annotate ${REGISTRY}/${IMAGE}:${VERSION} ${REGISTRY}/${IMAGE}:${VERSION}-amd64 --os linux --arch amd64
docker manifest annotate ${REGISTRY}/${IMAGE}:${VERSION} ${REGISTRY}/${IMAGE}:${VERSION}-arm64 --os linux --arch arm64

docker manifest push --insecure ${REGISTRY}/${IMAGE}:${VERSION}

sleep 1

echo "Creating manifest for latest..."
docker manifest create --amend --insecure ${REGISTRY}/${IMAGE}:latest \
  ${REGISTRY}/${IMAGE}:${VERSION}-amd64 \
  ${REGISTRY}/${IMAGE}:${VERSION}-arm64

docker manifest annotate ${REGISTRY}/${IMAGE}:latest ${REGISTRY}/${IMAGE}:${VERSION}-amd64 --os linux --arch amd64
docker manifest annotate ${REGISTRY}/${IMAGE}:latest ${REGISTRY}/${IMAGE}:${VERSION}-arm64 --os linux --arch arm64

docker manifest push --insecure ${REGISTRY}/${IMAGE}:latest

# Function to delete a tag by getting its manifest digest and deleting the manifest
delete_tag() {
  local tag=$1
  echo "Deleting single-arch tag: $tag"
  local url="http://${REGISTRY}/v2/${IMAGE}/manifests/${tag}"
  echo "Fetching digest from URL: $url"

  digest=$(curl -sI -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  "http://${REGISTRY}/v2/${IMAGE}/manifests/${tag}" | grep -i '^Docker-Content-Digest:' | sed 's/Docker-Content-Digest: //I' | tr -d $'\r')

  echo "Digest for tag $tag: $digest"
  if [ -n "$digest" ]; then
    echo "Deleting manifest with digest: $digest"
    curl -X DELETE "http://${REGISTRY}/v2/${IMAGE}/manifests/${digest}"
    echo "Deleted tag $tag (digest: $digest)"
  else
    echo "Failed to find digest for tag $tag, skipping deletion."
  fi
}

echo "Cleaning up single-arch tags..."
sleep 1
delete_tag "${VERSION}-amd64"
sleep 1
delete_tag "${VERSION}-arm64"

echo "Removing local images if they exist..."

if docker image inspect ${REGISTRY}/${IMAGE}:${VERSION}-amd64 > /dev/null 2>&1; then
  docker rmi ${REGISTRY}/${IMAGE}:${VERSION}-amd64
fi

if docker image inspect ${REGISTRY}/${IMAGE}:${VERSION}-arm64 > /dev/null 2>&1; then
  docker rmi ${REGISTRY}/${IMAGE}:${VERSION}-arm64
fi


echo "Cleaning up dangling images..."
docker builder prune -f

echo "===================================================="
echo "|           ✅ Docker Build Summary                |"
echo "===================================================="
printf "| %-17s %-30s |\n" "Image Name:"     "$IMAGE"
printf "| %-17s %-30s |\n" "Registry:"       "$REGISTRY"
printf "| %-17s %-30s |\n" "Version Tag:"    "$VERSION"
printf "| %-17s %-30s |\n" "Latest Tag:"     "latest"
printf "| %-17s %-30s |\n" "Built & Pushed:" "${VERSION}-amd64"
printf "| %-17s %-30s |\n" "Built & Pushed:" "${VERSION}-arm64"
printf "| %-17s %-30s |\n" "Manifest:"       "$VERSION"
printf "| %-17s %-30s |\n" "Manifest:"       "latest"
printf "| %-17s %-30s |\n" "Cleaned:"        "${VERSION}-amd64 (remote + local)"
printf "| %-17s %-30s |\n" "Cleaned:"        "${VERSION}-arm64 (remote + local)"
echo "===================================================="