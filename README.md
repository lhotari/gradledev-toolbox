# gradledev-toolbox
Gradle core developer toolbox

## Installation

Clone this repository to some directory.

Include the functions in your ~/.zshrc or ~/.bashrc file:
```
export GRADLEDEV_DIR=/path/to/gradle/working/dir
. /path/to/gradledev-toolbox/functions/gradledev-functions.sh
```
additional functions
```
. /path/to/gradledev-toolbox/functions/gradledev-perftest-functions.sh
. /path/to/gradledev-toolbox/functions/native-benchmark-functions.sh
```

## Features

### Running tests for changed sub-modules in a separate directory

```
gradledev_run_checks_in_clone
```

### Running performance benchmark

```
gradledev_benchmark
```

### Example of custom git-bisect script that checks a performance test figure

https://github.com/lhotari/gradledev-toolbox/blob/master/scripts/gradledev_perf_bisect.sh

Fixed rules: https://github.com/lhotari/gradledev-toolbox/blob/master/functions/native-benchmark-functions.sh#L24

usage (in Gradle working directory):
```
git bisect start HEAD REL_2.9-rc-1 --
git bisect run $GRADLEDEV_TOOLBOX_DIR/scripts/gradledev_perf_bisect.sh $PWD /path/to/testbuild
```
test build can be one of generated performance test builds.






