#!/bin/bash
# Copyright (c) 2019-2020, NVIDIA CORPORATION. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#  * Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#  * Neither the name of NVIDIA CORPORATION nor the names of its
#    contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
# OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

REPO_VERSION=${NVIDIA_TRITON_SERVER_VERSION}
if [ "$#" -ge 1 ]; then
    REPO_VERSION=$1
fi
if [ -z "$REPO_VERSION" ]; then
    echo -e "Repository version must be specified"
    echo -e "\n***\n*** Test Failed\n***"
    exit 1
fi
if [ ! -z "$TEST_REPO_ARCH" ]; then
    REPO_VERSION=${REPO_VERSION}_${TEST_REPO_ARCH}
fi

TEST_RESULT_FILE='test_results.txt'
export CUDA_VISIBLE_DEVICES=0

CLIENT_LOG="./client.log"
PLUGIN_TEST=trt_plugin_test.py

# On windows the paths invoked by the script (running in WSL) must use
# /mnt/c when needed but the paths on the tritonserver command-line
# must be C:/ style.
if [[ "$(< /proc/sys/kernel/osrelease)" == *microsoft* ]]; then
    DATADIR=${DATADIR:="/mnt/c/data/inferenceserver/${REPO_VERSION}/qa_trt_plugin_model_repository"}
    SERVER=${SERVER:=/mnt/c/tritonserver/bin/tritonserver.exe}
else
    DATADIR=${DATADIR:="/data/inferenceserver/${REPO_VERSION}/qa_trt_plugin_model_repository"}
    TRITON_DIR=${TRITON_DIR:="/opt/tritonserver"}
    SERVER=${TRITON_DIR}/bin/tritonserver
fi

SERVER=/opt/tritonserver/bin/tritonserver
source ../common/util.sh

RET=0
rm -fr *.log

LOG_IDX=0

## Plugin Tests Without LD_PRELOAD
SERVER_ARGS="--model-repository=$DATADIR --exit-timeout-secs=120 --backend-config=tensorrt,plugins=$DATADIR/libclipplugin.so"
SERVER_LOG="./inference_server_$LOG_IDX.log"

run_server
if [ "$SERVER_PID" == "0" ]; then
    echo -e "\n***\n*** Failed to start $SERVER\n***"
    cat $SERVER_LOG
    exit 1
fi

set +e
python $PLUGIN_TEST >$CLIENT_LOG 2>&1
if [ $? -ne 0 ]; then
    cat $CLIENT_LOG
    echo -e "\n***\n*** Test Failed\n***"
    RET=1
else
    check_test_results $TEST_RESULT_FILE 3
    if [ $? -ne 0 ]; then
        cat $CLIENT_LOG
        echo -e "\n***\n*** Test Result Verification Failed\n***"
        RET=1
    fi
fi
set -e

kill $SERVER_PID
wait $SERVER_PID

LOG_IDX=$((LOG_IDX+1))

## LD_PRELOAD Custom Plugin Test
## Success test
SERVER_LD_PRELOAD=$DATADIR/libclipplugin.so
SERVER_ARGS="--model-repository=$DATADIR --exit-timeout-secs=120"
SERVER_LOG="./inference_server_$LOG_IDX.log"

run_server
if [ "$SERVER_PID" == "0" ]; then
    echo -e "\n***\n*** Failed to start $SERVER\n***"
    cat $SERVER_LOG
    exit 1
fi

rm -f $CLIENT_LOG
set +e
python $PLUGIN_TEST PluginModelTest.test_raw_fff_clip >>$CLIENT_LOG 2>&1
if [ $? -ne 0 ]; then
    cat $CLIENT_LOG
    echo -e "\n***\n*** Test Failed\n***"
    RET=1
else
    check_test_results $TEST_RESULT_FILE 1
    if [ $? -ne 0 ]; then
        cat $CLIENT_LOG
        echo -e "\n***\n*** Test Result Verification Failed\n***"
        RET=1
    fi
fi
set -e

kill $SERVER_PID
wait $SERVER_PID

LOG_IDX=$((LOG_IDX+1))

## LD_PRELOAD Custom Plugin Test
## Failure test

unset SERVER_LD_PRELOAD
SERVER_LOG="./inference_server_$LOG_IDX.log"

run_server
set +e
if [ "$SERVER_PID" != "0" ]; then
    echo -e "\n***\n*** Test Failed\n"
    echo -e "Unexpected successful server start $SERVER\n***"
    cat $SERVER_LOG
    kill $SERVER_PID
    wait $SERVER_PID
    exit 1
fi
set -e

rm -f $CLIENT_LOG

if [ $RET -eq 0 ]; then
    echo -e "\n***\n*** Test Passed\n***"
else
    echo -e "\n***\n*** Test FAILED\n***"
fi

exit $RET
