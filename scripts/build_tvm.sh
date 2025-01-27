#!/usr/bin/env bash

source /multibuild/manylinux_utils.sh

function usage() {
    echo "Usage: $0 [--cuda CUDA] [--tvm-url URL] [--hash HASH]"
    echo
    echo -e "--cuda {none 10.0 10.1 10.2}"
    echo -e "\tSpecify the CUDA version in the TVM (default: none)."
    echo -e "--hash HASH"
    echo -e "\tSpecify a git commit hash for TVM."
    echo -e "--tvm-url URL"
    echo -e "\tSpecify a git repository URL for TVM (default: ${DEFAULT_TVM_URL})."
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

CUDA_OPTIONS=("none" "10.0" "10.1" "10.2")
CUDA="none"
HASH_TAG=""
DEFAULT_TVM_URL="https://github.com/apache/tvm"
TVM_URL="${DEFAULT_TVM_URL}"

while [[ $# -gt 0 ]]; do
    arg="$1"
    case $arg in
        --cuda)
            CUDA=$2
            shift
            shift
            ;;
        --hash)
            HASH_TAG=$2
            shift
            shift
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

if ! in_array "${CUDA}" "${CUDA_OPTIONS[*]}" ; then
    echo "Invalid CUDA option: ${CUDA}"
    echo
    echo 'CUDA can only be {"none", "10.0", "10.1", "10.2"}'
    exit -1
fi

if [[ ${CUDA} == "none" ]]; then
    echo "Building TVM for CPU only"
else
    echo "Building TVM with CUDA ${CUDA}"
fi

# check out the tvm
cd /workspace
echo "Cloning TVM from ${TVM_URL}"
git clone "${TVM_URL}" tvm --recursive

if [[ ${HASH_TAG} ]]; then
    cd /workspace/tvm && git checkout ${HASH_TAG} && git submodule update --recursive
fi

# config the cmake
cd /workspace/tvm
echo set\(USE_LLVM \"llvm-config --ignore-libllvm\"\) >> config.cmake
echo set\(USE_RPC ON\) >> config.cmake
echo set\(USE_SORT ON\) >> config.cmake
echo set\(USE_GRAPH_RUNTIME ON\) >> config.cmake
echo set\(USE_ETHOSN /opt/arm/ethosn-driver\) >> config.cmake
echo set\(USE_ARM_COMPUTE_LIB /opt/arm/acl\) >> config.cmake
if [[ ${CUDA} != "none" ]]; then
    echo set\(USE_CUDA ON\) >> config.cmake
    echo set\(USE_CUBLAS ON\) >> config.cmake
    echo set\(USE_CUDNN ON\) >> config.cmake
fi

# compile the tvm
mkdir -p build
cd build
cmake ..
make -j$(nproc)

# patch the package name
cd /workspace/tvm
/workspace/scripts/patch_name.sh ${CUDA}

UNICODE_WIDTH=32  # Dummy value, irrelevant for Python 3
CPYTHON36_PATH="$(cpython_path 3.6 ${UNICODE_WIDTH})"
CPYTHON37_PATH="$(cpython_path 3.7 ${UNICODE_WIDTH})"
CPYTHON38_PATH="$(cpython_path 3.8 ${UNICODE_WIDTH})"
PYTHON36="${CPYTHON36_PATH}/bin/python"
PYTHON37="${CPYTHON37_PATH}/bin/python"
PYTHON38="${CPYTHON38_PATH}/bin/python"
PIP36="${CPYTHON36_PATH}/bin/pip"
PIP37="${CPYTHON37_PATH}/bin/pip"
PIP38="${CPYTHON38_PATH}/bin/pip"

# build the python wheel
cd /workspace/tvm/python
PATH="${CPYTHON36_PATH}/bin:$PATH" ${PYTHON36} setup.py bdist_wheel
PATH="${CPYTHON37_PATH}/bin:$PATH" ${PYTHON37} setup.py bdist_wheel
PATH="${CPYTHON38_PATH}/bin:$PATH" ${PYTHON38} setup.py bdist_wheel

# repair python wheels
mkdir -p repaired_wheels
auditwheel repair --plat ${AUDITWHEEL_PLAT} dist/tlcpack*cp36*.whl -w repaired_wheels/
auditwheel repair --plat ${AUDITWHEEL_PLAT} dist/tlcpack*cp37*.whl -w repaired_wheels/
auditwheel repair --plat ${AUDITWHEEL_PLAT} dist/tlcpack*cp38*.whl -w repaired_wheels/

# test the built wheels
cd /workspace/tvm/python
${PIP36} install repaired_wheels/tlcpack*cp36*.whl
${PIP37} install repaired_wheels/tlcpack*cp37*.whl
${PIP38} install repaired_wheels/tlcpack*cp38*.whl
${PYTHON36} -c "import tvm; from tvm import relay; from tvm import topi; relay.var('x'); tvm.te.var('n')"
${PYTHON37} -c "import tvm; from tvm import relay; from tvm import topi; relay.var('x'); tvm.te.var('n')"
${PYTHON38} -c "import tvm; from tvm import relay; from tvm import topi; relay.var('x'); tvm.te.var('n')"

# move the wheels
mv /workspace/tvm/python/repaired_wheels/tlcpack*.whl /workspace/pip

# clean up
rm -rf /workspace/tvm
