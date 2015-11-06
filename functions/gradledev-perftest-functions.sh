function gradledev_perf_test {
    (
    GITDIR=$(git rev-parse --show-toplevel)
    [ ! -d "$GITDIR" ] && echo "Not a git directory" && exit 1
    cd "$GITDIR"
    ./gradlew --stop
    TESTPARAM=""
    if [ -n "$1" ]; then
        TESTPARAM="-D:performance:performanceTest.single=$1"
        shift
    fi
    ./gradlew -S -x :performance:prepareSamples :performance:performanceTest -PperformanceTest.verbose $TESTPARAM "$@"
    )
}

function gradledev_daemon_pid {
    pgrep -f GradleDaemon
}

function gradle_opts_jfr {
    export GRADLE_OPTS="-Dorg.gradle.jvmargs='-Xmx2g -XX:+UnlockCommercialFeatures -XX:+FlightRecorder -XX:+UnlockDiagnosticVMOptions -XX:+DebugNonSafepoints'"
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

