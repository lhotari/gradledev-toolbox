function jfr-report-tool {
    $GRADLEDEV_TOOLBOX_DIR/jfr-report-tool/jfr-report-tool "$@"
}

function gradledev_open {
    if ! type xdg-open > /dev/null; then
        # assume MacOSX
        open "$@"
    else
        # Linux
        xdg-open "$@"
    fi
}

function gradledev_create_flamegraph {
    (
    local OPTIND OPTARG opt
    reportargs="-c '(execution.DefaultBuildExecuter.execute|progress.DefaultBuildOperationExecutor.run|execution.DefaultBuildConfigurationActionExecuter.select)' --min-samples-frame-depth=5 -m 5"
    while getopts ":n" opt; do
        case "${opt}" in
            n)
            reportargs="-e none -m 1"
            ;;
        esac
    done
    shift $((OPTIND-1))
    JFRFILE="$1"
    jfr-report-tool $reportargs "$JFRFILE"
    convert -size 1000x1000 -resize 1000x1000 +profile '*' "$JFRFILE.svg" "$JFRFILE.jpg"
    gradledev_open "$JFRFILE.svg"
    )
}

function gradledev_perf_test {
    (
    gradledev_check_cpu || exit 1
    gradledev_cd_gradle_dir
    ./gradlew --stop
    TESTPARAM=""
    if [ -n "$1" ]; then
        TESTPARAM="-D:performance:performanceTest.single=$1"
        shift
    fi
    ./gradlew -S -x :performance:prepareSamples :performance:cleanPerformanceTest :performance:performanceTest -PperformanceTest.verbose $TESTPARAM "$@"
    )
}

function gradledev_check_cpu {
    (
    [ -e /sys/devices/system/cpu ] || exit 0
    local i
    for i in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        MODE=`cat $i`
        if [ "$MODE" != "performance" ]; then
            echo "CPU $i is not in performance mode! was ""\"$MODE\""
            exit 1 
        fi
    done
    exit 0
    )    
}

function gradledev_perfbuild_run {
    (
    local params
    if [ "$#" -eq 0 ]; then
      params=( "build" )
    else
      params=( "$@" )
    fi
    gradledev_find_install
    $GRADLEDEV_INSTALL_DIR/bin/gradle -I init.gradle -u "${params[@]}"
    )
}

function gradledev_timestamp {
	date +%Y-%m-%d-%H:%M:%S
}

function gradledev_benchmark {
    (
    gradledev_check_cpu || exit 1
    
    local OPTIND opt loophandler finishhandler jfrenabled loopcount params
    loopcount=5
    while getopts ":jl:c:f:" opt; do
        case "${opt}" in
            l)
            loophandler="${OPTARG}"
            ;;
            f)
            finishhandler="${OPTARG}"
            ;;
            j)
            jfrenabled=1
            ;;
            c)
            loopcount=$OPTARG
            ;;
        esac
    done
    shift $((OPTIND-1))
    
    if [ "$#" -eq 0 ]; then
      params=( "build" )
    else
      params=( "$@" )
    fi
    
    gradledev_find_install
    gradledev_daemon_kill
    gradledev_perfbuild_run "${params[@]}"
    TIMESLOG="times$(gradledev_timestamp).log"
    if [ -f $GRADLEDEV_INSTALL_DIR/.githash_short ]; then
        echo "Git hash $(cat $GRADLEDEV_INSTALL_DIR/.githash_short)" > $TIMESLOG
    else
        echo "Gradle version $(gradledev_installed_version)" > $TIMESLOG
    fi
    declare -p GRADLE_OPTS >> $TIMESLOG
    gradledev_perfbuild_printTimes | tee -a $TIMESLOG
    params=("${params[@]}" --parallel --max-workers=4)
    if [[ $jfrenabled -eq 1 ]]; then
        gradledev_jfr_start
    fi
    local i
    for ((i=1;i<=$loopcount;i+=1)); do
        if [[ $i > 1 ]]; then
            echo "Wait 5 seconds"
            sleep 5
        fi
        if [ -n "$loophandler" ]; then
            eval "$loophandler"
        fi
        gradledev_perfbuild_run "${params[@]}"
        echo "This round"
        gradledev_perfbuild_printTimes | tee -a $TIMESLOG
        echo "All times"
        cat $TIMESLOG
    done
    if [[ $jfrenabled -eq 1 ]]; then
        gradledev_jfr_stop
    fi
    if [ -n "$finishhandler" ]; then
        eval "$finishhandler"
    fi
    )
}

function gradledev_benchmark_do_change {
    echo "Replace this function"
}

function gradledev_benchmark_changed {
    gradledev_benchmark -l gradledev_benchmark_do_change "$@"
}

function gradledev_perfbuild_printTimes {
    (
    [ -z "$ZSH_VERSION" ] || setopt ksharrays
    TIMES=($(cat build/buildEventTimestamps.txt))
    FULLTIME=$(( (${TIMES[2]} - ${TIMES[0]})/1000000 ))
    CONFTIME=$(( (${TIMES[1]} - ${TIMES[0]})/1000000 ))
    BUILDTIME=$(( (${TIMES[2]} - ${TIMES[1]})/1000000 ))
    GRADLETIME=${TIMES[3]}
    BUILDMEM=$(( $(cat build/totalMemoryUsed.txt) / 1024 / 1024 ))
    echo "full: $FULLTIME conf: $CONFTIME build: $BUILDTIME gradle: $GRADLETIME buildmem: $BUILDMEM"
    )
}

function gradledev_installed_version {
    gradledev_find_install
    $GRADLEDEV_INSTALL_DIR/bin/gradle -v |egrep '^Gradle'|awk '{ print $2 }'
}

function gradledev_rename_caches {
    GRADLE_VER=`gradledev_installed_version 2> /dev/null`
    GRADLE_CACHE_DIR=`ls -trd1 .gradle/2.* 2> /dev/null`
    if [[ -n "$GRADLE_VER" && ! -d ".gradle/$GRADLE_VER" && -d "$GRADLE_CACHE_DIR" ]]; then
        mv "$GRADLE_CACHE_DIR" ".gradle/$GRADLE_VER"
    fi
}

function gradledev_daemon_pid {
    jps | grep GradleDaemon | awk '{ print $1 }'
}

function gradledev_daemon_kill {
    local pid
    for pid in `gradledev_daemon_pid`; do
        kill $pid
    done
    if [ -n "$(gradledev_daemon_pid)" ]; then
        echo "Killing remaining GradleDaemon processes. Waiting 2 seconds."
        sleep 2
        for pid in `gradledev_daemon_pid`; do
            echo "Killing $pid"
            kill -9 $pid
        done
    fi
}

function gradledev_set_opts {
    local mode=$1
    shift
    local options="$@"
    if [ $mode = "nodaemon" ]; then
        export GRADLE_OPTS="$options"
    elif [ $mode = "both" ]; then
        export GRADLE_OPTS="$options -Dorg.gradle.jvmargs='$options'"
    else
        export GRADLE_OPTS="-Dorg.gradle.jvmargs='$options'"
    fi
}

function gradle_opts_jfr {
    local mode=daemon
    [ $# -lt 1 ] || mode=$1
    gradledev_set_opts $mode '-Xmx2g -XX:+UnlockCommercialFeatures -XX:+FlightRecorder -XX:+UnlockDiagnosticVMOptions -XX:+DebugNonSafepoints'
}

function gradle_opts_jfr_enabled {
    local mode=daemon
    [ $# -lt 1 ] || mode=$1
    gradledev_set_opts $mode "-Xmx2g -XX:+UnlockCommercialFeatures -XX:+FlightRecorder -XX:+UnlockDiagnosticVMOptions -XX:+DebugNonSafepoints -XX:FlightRecorderOptions=defaultrecording=true,settings=$GRADLEDEV_TOOLBOX_DIR/etc/jfr/profiling.jfc,disk=true,maxsize=500M,dumponexit=true"
}

function gradle_opts_jitwatch {
    local mode=daemon
    [ $# -lt 1 ] || mode=$1
    gradledev_set_opts $mode '-Xmx2g -XX:+UnlockDiagnosticVMOptions -XX:+LogCompilation -XX:+TraceClassLoading -XX:+LogVMOutput -XX:-DisplayVMOutput'
}

function gradle_opts_gclogging {
    local mode=daemon
    [ $# -lt 1 ] || mode=$1
    # %p in loggc requires java 8
    gradledev_set_opts $mode '-Xmx2g -verbose:gc -Xloggc:gc_%p.log -XX:+PrintGCDateStamps -XX:+PrintGCDetails -XX:+PrintAdaptiveSizePolicy'
}

function gradle_opts_debug {
    local mode=daemon
    [ $# -lt 1 ] || mode=$1
    gradledev_set_opts $mode '-Xmx2g -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5005'
}

function gradle_opts_debug_suspend {
    local mode=daemon
    [ $# -lt 1 ] || mode=$1
    gradledev_set_opts $mode '-Xmx2g -agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=5005'
}

function gradledev_jfr_start {
    DAEMON_PID=`gradledev_daemon_pid`
    jcmd $DAEMON_PID JFR.start name=GradleDaemon_$DAEMON_PID settings=$GRADLEDEV_TOOLBOX_DIR/etc/jfr/profiling.jfc maxsize=1G
}

function gradledev_jfr_stop {
    DAEMON_PID=`gradledev_daemon_pid`
    FILENAME="$PWD/GradleDaemon_${DAEMON_PID}_$(date +%F-%T).jfr"
    jcmd $DAEMON_PID JFR.stop name=GradleDaemon_$DAEMON_PID filename=$FILENAME
    if [[ "$1" == "open" ]]; then
        jmc -open "$FILENAME" &
    else
        echo "command to open: jmc -open '$FILENAME'"
    fi
}

