#!/bin/bash
# example:
# git bisect start HEAD REL_2.9-rc-1 --
# git bisect run $GRADLEDEV_TOOLBOX_DIR/scripts/gradledev_perf_bisect.sh $PWD /path/to/testbuild 
export GRADLEDEV_DIR="$1"
TESTBUILDDIR="$2"
[ -d "$GRADLEDEV_DIR" ] && [ -d "$TESTBUILDDIR" ] || { echo "usage: $0 gradledir testbuilddir"; exit 1; }
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
GRADLEDEV_TOOLBOX_DIR=$(dirname "$DIR")
. $GRADLEDEV_TOOLBOX_DIR/functions/gradledev-functions.sh
. $GRADLEDEV_TOOLBOX_DIR/functions/gradledev-perftest-functions.sh
. $GRADLEDEV_TOOLBOX_DIR/functions/native-benchmark-functions.sh
cd "$TESTBUILDDIR"
gradledev_check_perf_test
