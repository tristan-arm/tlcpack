#!/usr/bin/env bash

set -e
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(dirname "${SCRIPT_DIR}")/docker"
PIP_DIR="$(dirname "${SCRIPT_DIR}")/pip"

DOCKER_TAG=`cat "${DOCKER_DIR}/version.txt"`
COMMIT_HASH=`cat "${SCRIPT_DIR}/tvm_commit_hash.txt"`
DEFAULT_TVM_URL="https://github.com/apache/tvm"
TVM_URL="${DEFAULT_TVM_URL}"

function usage() {
    echo "Usage: $0 [--cuda CUDA] [--tvm-url URL] [--hash GIT_HASH]"
    echo
    echo -e "--cuda {none 10.0 10.1 10.2}"
    echo -e "\tSpecify the CUDA version in building the wheels. If not specified, build all version."
    echo
    echo -e "--hash GIT_HASH"
    echo -e "\tBuild packages using a specific TVM git hash."
    echo -e "\tThis option overrides the value in scripts/tvm_commit_hash.txt"
    echo
    echo -e "--tvm-url URL"
    echo -e "\tBuild packages using a custom TVM repository URL."
    echo -e "\tDefaults to \"${DEFAULT_TVM_URL}\""
    echo
}

function in_array() {
    KEY=$1
    ARRAY=$2
    for e in ${ARRAY[*]}; do
        if [[ "$e" == "$1" ]]; then
            return 0
        fi
    done
    return 1
}

function build_wheel() {
    CUDA="$1"
    ARGS="--tvm-url ${TVM_URL} --hash ${COMMIT_HASH}"
    if [[ ${CUDA} == "none" ]]; then
        DOCKER_IMAGE="tlcpack/package-cpu:${DOCKER_TAG}"
        CUDA_ENV=""
        echo "Building wheel for CPU only"
    else
        DOCKER_IMAGE="tlcpack/package-cu${CUDA/./}:${DOCKER_TAG}"
        CUDA_ENV=" --gpus all "
        ARGS="${ARGS} --cuda ${CUDA}"
        echo "Building wheel with CUDA ${CUDA}"
    fi

    echo "Running docker image ${DOCKER_IMAGE}"
    ${DOCKER_DIR}/bash.sh ${DOCKER_IMAGE} scripts/build_tvm.sh ${ARGS}
}

ALL_CUDA_OPTIONS=("none" "10.0" "10.1" "10.2")
CUDA=""

while [[ $# -gt 0 ]]; do
    arg="$1"
    case $arg in
        --cuda)
            CUDA=("$2")
            shift
            shift
            ;;
        --hash)
            COMMIT_HASH=("$2")
            shift 2
            ;;
        -h|--help)
            usage
            exit -1
            ;;
        --tvm-url)
            TVM_URL=("$2")
            shift 2
            ;;
        *) # unknown option
            echo "Unknown argument: $arg"
            echo
            usage
            exit -1
            ;;
    esac
done

mkdir -p ${PIP_DIR}
if [[ ${CUDA} ]]; then
    if ! in_array "${CUDA}" "${ALL_CUDA_OPTIONS[*]}" ; then
        echo "Invalid CUDA option: ${CUDA}"
        echo
        echo 'CUDA can only be {"none", "10.0", "10.1", "10.2"}'
        exit -1
    fi
    build_wheel ${CUDA}
else
    for cuda in ${ALL_CUDA_OPTIONS[@]}; do
        build_wheel ${cuda}
    done
fi
