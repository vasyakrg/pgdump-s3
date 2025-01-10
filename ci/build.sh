#!/bin/bash

set -e

if [[ -n "${BUILD_SCRIPT}" ]]; then SCRIPTS_PATH=${BUILD_SCRIPT%/*}; else SCRIPTS_PATH=ci/build/image; fi
DOCKER_BASEIMAGE=${DOCKER_BASEIMAGE:-ubuntu:18.04}
DOCKER_MAINTAINER=${DOCKER_MAINTAINER:-$GITLAB_USER_EMAIL}
DOCKER_MAINTAINER=${DOCKER_MAINTAINER:-service@ds.mlmsoft.cloud}
DOCKER_IMAGE_NAME=${DOCKER_IMAGE_NAME:-${CI_PROJECT_PATH#*/}}
DOCKER_IMAGE_PREFIX=${DOCKER_IMAGE_PREFIX:-mlmsoft}
DOCKER_FILE=${DOCKER_FILE:-Dockerfile}

if [[ -z "${VERSION}" ]]; then 
	if [[ -f "VERSION" ]]; then VERSION=$(cat VERSION); else VERSION=latest; fi
fi
DOCKER_IMAGE_TAG=${DOCKER_IMAGE_TAG:-$VERSION}
if [[ "${CI_COMMIT_REF_SLUG}" != "master" ]]; then
    if [[ "${DOCKER_IMAGE_TAG}" == "latest" ]]; then TAG=''; else TAG="${DOCKER_IMAGE_TAG}_"; fi
    echo TAG=${TAG}
    if [[ -z "${DOCKER_NO_BRANCH_TAG}" ]]; then
        DOCKER_IMAGE_TAG=${TAG}${CI_COMMIT_REF_SLUG}
        echo Change DOCKER_IMAGE_TAG=${DOCKER_IMAGE_TAG}
    fi
fi

if [[ -n "${CI}" ]]; then 
	DOCKER_BUILD_CONTEXT=${DOCKER_BUILD_CONTEXT:-'.'}
elif [[ -f ${BASH_SOURCE[0]%/*}/.env ]]; then 
	source ${BASH_SOURCE[0]%/*}/.env
fi	

BUILD_ARGS=()
for var in $@; do
    [[ "${var}" =~ ^[a-zA-Z0-9+_-]+=.+$ ]] && BUILD_ARGS+=( --build-arg ${var} )
done

for (( i=0; i<10; i++ )); do
	arg=DOCKER_ARG$i
	[[ -n ${!arg} ]] && BUILD_ARGS+=( --build-arg ${!arg} )
done

[[ ${DOCKER_BASEIMAGE} != *:* ]] && DOCKER_BASEIMAGE=${DOCKER_BASEIMAGE}:${VERSION}
#[[ ${DOCKER_BASEIMAGE} == *:latest ]] && docker pull ${DOCKER_BASEIMAGE}

# Скачивание базового образа
if [[ -z ${DOCKER_NO_PULL_BASEIMAGE:+x} ]]; then
    docker login -u gitlab-ci-token -p ${CI_JOB_TOKEN} ${CI_REGISTRY}
    docker pull ${DOCKER_BASEIMAGE}
fi

echo DOCKER_BASEIMAGE=${DOCKER_BASEIMAGE}
echo DOCKER_IMAGE_NAME=${DOCKER_IMAGE_NAME}
echo DOCKER_IMAGE_TAG=${DOCKER_IMAGE_TAG}
echo DOCKER_BUILD_CONTEXT=${DOCKER_BUILD_CONTEXT}
echo DOCKER_NO_BRANCH_TAG=${DOCKER_NO_BRANCH_TAG}
echo DOCKER_NO_PULL_BASEIMAGE=${DOCKER_NO_PULL_BASEIMAGE}
echo DOCKER_FILE=${DOCKER_FILE}
echo DOCKER_TAG_AS_LATEST=${DOCKER_TAG_AS_LATEST}
echo VERSION=${VERSION}
echo Building args: ${BUILD_ARGS[@]}

DOCKER_IMAGE=${DOCKER_IMAGE_PREFIX}/${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}
if ! docker build -f ${DOCKER_FILE} --build-arg DOCKER_BASEIMAGE=${DOCKER_BASEIMAGE} --build-arg DOCKER_MAINTAINER=${DOCKER_MAINTAINER} \
			 --build-arg VERSION=${VERSION} ${BUILD_ARGS[@]} --no-cache --force-rm -t ${DOCKER_IMAGE} ${DOCKER_BUILD_CONTEXT} ; then
	# Remove all orphaned images after unsuccessfull build
	docker image prune -f > /dev/null 2>&1
	exit 1;
fi

#docker tag ${DOCKER_IMAGE_NAME} ${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}

if [[ -n "${CI}" ]]; then 
	chmod +x "${SCRIPTS_PATH}/import.sh"
	DOCKER_IMAGE=${DOCKER_IMAGE} "${SCRIPTS_PATH}/import.sh"
fi

