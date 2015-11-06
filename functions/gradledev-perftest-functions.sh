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

function gradledev_check_cpu {
    (
    [ -e /sys/devices/system/cpu ] || exit 0
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
    if [ "$#" -eq 0 ]; then
      params=( "build" )
    else
      params=( "$@" )
    fi
    [ -d /tmp/gradle-install ] || gradledev_install
    /tmp/gradle-install/bin/gradle -I init.gradle -u "${params[@]}"
    )
}

function gradledev_timestamp {
	date +%Y-%m-%d-%H:%M:%S
}

function gradledev_benchmark {
    (
    gradledev_check_cpu || exit 1
    if [ "$#" -eq 0 ]; then
      params=( "build" )
    else
      params=( "$@" )
    fi
    gradledev_daemon_kill
    gradledev_rename_caches
    gradledev_perfbuild_run "${params[@]}"
    TIMESLOG=times$(gradledev_timestamp).log
    echo "Git hash $(cat /tmp/gradle-install/.githash_short)" >> $TIMESLOG
    gradledev_perfbuild_printTimes | tee -a $TIMESLOG    
    params = ( "${params[@]}" --parallel --max-workers=4 )
    for ((i=1;i<=5;i+=1)); do
        echo "This round"
        gradledev_perfbuild_run "${params[@]}"
        gradledev_perfbuild_printTimes | tee -a $TIMESLOG
        echo "All times"
        cat $TIMESLOG
        if [[ $i != 5 ]]; then
            echo "Wait 5 seconds"
            sleep 5
        fi
    done
    )
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
    [ -d /tmp/gradle-install ] || gradledev_install
    /tmp/gradle-install/bin/gradle -v |egrep '^Gradle'|awk '{ print $2 }'
}

function gradledev_rename_caches {
    GRADLE_VER=`gradledev_installed_version`
    if [ ! -d .gradle/$GRADLE_VER ] && `ls .gradle/2.* 2> /dev/null` ; then
        mv .gradle/2.* .gradle/$GRADLE_VER
    fi
}

function gradledev_daemon_pid {
    pgrep -f GradleDaemon
}

function gradledev_daemon_kill {
    pkill -f GradleDaemon
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

