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
    local init_part
    [ -f init.gradle ] && init_part=" -I init.gradle"
    $GRADLEDEV_INSTALL_DIR/bin/gradle$init_part -u "${params[@]}"
    )
}

function gradledev_timestamp {
	date +%Y-%m-%d-%H:%M:%S
}

function gradledev_benchmark {
    (
    gradledev_check_cpu || exit 1
    
    local OPTIND opt loophandler finishhandler jfrenabled yjpenabled hpenabled loopcount params loopdelay nokill
    loopcount=5
    loopdelay=5
    warmupcount=1
    while getopts ":jhnl:c:f:d:w:y:" opt; do
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
            y)
            yjpenabled="${OPTARG}"
            ;;
            h)
            hpenabled=1
            ;;
            n)
            nokill=1
            ;;
            c)
            loopcount=$OPTARG
            ;;
            d)
            loopdelay=$OPTARG
            ;;
            w)
            warmupcount=$OPTARG
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
    if [[ $nokill -ne 1 ]]; then
        gradledev_daemon_kill
    fi
    for ((i=1;i<=$warmupcount;i+=1)); do
        echo "Warmup $i/$warmupcount"
        gradledev_perfbuild_run "${params[@]}"
    done
    if [[ $warmupcount -eq 0 && ( $jfrenabled -eq 1 || $hpenabled -eq 1 || $yjpenabled -eq 1 ) ]]; then
        gradledev_perfbuild_run help
    fi
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
    if [[ $hpenabled -eq 1 ]]; then
        gradledev_hp_start
    fi
    if [[ -n "$yjpenabled" ]]; then
        gradledev_yjp_start_profiling "$yjpenabled"
    fi
    local i
    for ((i=1;i<=$loopcount;i+=1)); do
        echo "Execution $i/$loopcount"
        if [[ $i > 1 && $loopdelay > 0 ]]; then
            echo "Wait $loopdelay seconds"
            sleep $loopdelay
        fi
        if [ -n "$loophandler" ]; then
            eval "$loophandler"
        fi
        gradledev_perfbuild_run "${params[@]}"
        echo "This round"
        gradledev_perfbuild_printTimes | tee -a $TIMESLOG
        echo "All times"
        cat $TIMESLOG
        echo "Min times"
        gradledev_perfbuild_printMinTimes
    done
    if [[ $jfrenabled -eq 1 ]]; then
        gradledev_jfr_stop
    fi
    if [[ $hpenabled -eq 1 ]]; then
        gradledev_hp_stop
    fi
    if [[ -n "$yjpenabled" ]]; then
        gradledev_yjp_snapshot
        gradledev_yjp_stop_profiling
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
    if [ -f build/buildEventTimestamps.txt ]; then
        [ -z "$ZSH_VERSION" ] || setopt ksharrays
        TIMES=($(cat build/buildEventTimestamps.txt))
        FULLTIME=$(( (${TIMES[2]} - ${TIMES[0]})/1000000 ))
        CONFTIME=$(( (${TIMES[1]} - ${TIMES[0]})/1000000 ))
        BUILDTIME=$(( (${TIMES[2]} - ${TIMES[1]})/1000000 ))
        GRADLETIME=${TIMES[3]}
        BUILDMEM=$(( $(cat build/totalMemoryUsed.txt) / 1024 / 1024 ))
        echo "full: $FULLTIME conf: $CONFTIME build: $BUILDTIME gradle: $GRADLETIME buildmem: $BUILDMEM"
    fi
    )
}

function gradledev_perfbuild_printMinTimes {
    (
    if [ -n "$1" ]; then
        TIMESLOG="$1"
    fi
    gradledev_perfbuild_printMinTime full 2
    gradledev_perfbuild_printMinTime conf 3
    gradledev_perfbuild_printMinTime build 4
    gradledev_perfbuild_printMinTime gradle 5
    )
}

function gradledev_perfbuild_printMinTime {
    (
    fname=${1:-gradle}
    fnum=${2:-5}
    mintime=$(cat $TIMESLOG |awk -v fnum=$fnum -F': ' '{ print $fnum }'|awk '{ print $1 }' | awk 'NF' | tail -n +4 | awk '{ if ($1 < min || min == 0) min=$1; } END { print min; }')
    if [ -n "$mintime" ]; then
       cat $TIMESLOG|grep --color "$fname: $mintime"
    fi
    )
}

function gradledev_rename_caches {
    GRADLE_VER=`gradledev_installed_version 2> /dev/null`
    GRADLE_CACHE_DIR=`ls -trd1 .gradle/3.* 2> /dev/null`
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
    local default_options=${GRADLEDEV_OPTS:--Xmx2g -Xverify:none}
    local options="${default_options} $@"
    if [ $mode = "nodaemon" ]; then
        export GRADLE_OPTS="$options"
    elif [ $mode = "both" ]; then
        export GRADLE_OPTS="$options -Dorg.gradle.jvmargs='$options'"
    else
        export GRADLE_OPTS="-Dorg.gradle.jvmargs='$options'"
    fi
}

function gradle_opts_default {
    local mode=daemon
    [ $# -lt 1 ] || mode=$1
    gradledev_set_opts $mode
}

function gradle_opts_jfr {
    local mode=daemon
    [ $# -lt 1 ] || mode=$1
    gradledev_set_opts $mode 'XX:+UnlockCommercialFeatures -XX:+FlightRecorder -XX:FlightRecorderOptions=stackdepth=1024 -XX:+UnlockDiagnosticVMOptions -XX:+DebugNonSafepoints'
}

function gradle_opts_yjp {
    local mode=daemon
    [ $# -lt 1 ] || mode=$1
    local agent_file=linux-x86-64/libyjpagent.so
    if [[ "$(uname)" == "Darwin" ]]; then
        agent_file=mac/libyjpagent.jnilib
    fi 
    local yjp_agent="${YJP_HOME:-/opt/yjp}/bin/${agent_file}"
    local yjp_mode=${2:-sampling}
    local yjp_common_params="disablealloc,monitors,probe_disable=*,delay=0,onexit=snapshot,port=10010,onlylocal"
    local yjp_params="sampling,disabletracing"
    if [[ "$yjp_mode" == "tracing" ]]; then
        yjp_params="tracing"
    elif [[ "$yjp_mode" == "call_counting" ]]; then
        yjp_params="call_counting"
    fi
    gradledev_set_opts $mode "-agentpath:${yjp_agent}=${yjp_params},${yjp_common_params}"
}

function gradle_opts_yjp_enable {
    local mode=daemon
    [ $# -lt 1 ] || mode=$1
    local agent_file=linux-x86-64/libyjpagent.so
    if [[ "$(uname)" == "Darwin" ]]; then
        agent_file=mac/libyjpagent.jnilib
    fi 
    local yjp_agent="${YJP_HOME:-/opt/yjp}/bin/${agent_file}"
    local yjp_params="port=10010,onlylocal"
    gradledev_set_opts $mode "-agentpath:${yjp_agent}=${yjp_params}"
}

function gradle_opts_jfr_enabled {
    local mode=daemon
    local OPTIND OPTARG opt
    local jfr_basic_properties=",defaultrecording=true"
    local jfr_extra_properties=""
    local jfr_extra_options=""
    while getopts ":bsd:" opt; do
        case "${opt}" in
            d)
            jfr_extra_properties="${jfr_extra_properties},dumponexitpath=${OPTARG}"
            ;;
            b)
            jfr_extra_properties="${jfr_extra_properties},globalbuffersize=500M,maxchunksize=120M,threadbuffersize=200k"
            ;;
            s)
            jfr_basic_properties=""
            jfr_extra_options="-XX:StartFlightRecording=settings=$GRADLEDEV_TOOLBOX_DIR/etc/jfr/profiling.jfc,name=GradleProfiling"
            ;;
        esac
    done
    shift $((OPTIND-1))
    [ $# -lt 1 ] || mode=$1
    gradledev_set_opts $mode "-XX:+UnlockCommercialFeatures -XX:+FlightRecorder -XX:+UnlockDiagnosticVMOptions -XX:+DebugNonSafepoints -XX:FlightRecorderOptions=stackdepth=1024,disk=true,dumponexit=true${jfr_basic_properties}${jfr_extra_properties} ${jfr_extra_options}"
}

function gradle_opts_jitwatch {
    local mode=daemon
    [ $# -lt 1 ] || mode=$1
    gradledev_set_opts $mode 'XX:+UnlockDiagnosticVMOptions -XX:+LogCompilation -XX:+TraceClassLoading -XX:+LogVMOutput -XX:-DisplayVMOutput'
}

function gradle_opts_gclogging {
    local mode=daemon
    [ $# -lt 1 ] || mode=$1
    # %p in loggc requires java 8
    gradledev_set_opts $mode 'verbose:gc -Xloggc:gc_%p.log -XX:+PrintGCDateStamps -XX:+PrintGCDetails -XX:+PrintAdaptiveSizePolicy'
}

function gradle_opts_debug {
    local mode=daemon
    [ $# -lt 1 ] || mode=$1
    gradledev_set_opts $mode 'agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5005'
}

function gradle_opts_debug_suspend {
    local mode=daemon
    [ $# -lt 1 ] || mode=$1
    gradledev_set_opts $mode 'agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=5005'
}

function gradle_opts_honestprofiler {
    local mode=daemon
    local OPTIND OPTARG opt
    local hp_extra_properties=""
    local hp_interval=7
    while getopts ":ci:" opt; do
        case "${opt}" in
            c)
            HP_PORT=${HONEST_PROFILER_PORT:-18080}
            hp_extra_properties=",port=$HP_PORT,host=127.0.0.1,start=0"
            ;;
            i)
            hp_interval="${OPTARG}"
            ;;
        esac
    done
    shift $((OPTIND-1))
    [ $# -lt 1 ] || mode=$1
    HP_HOME_DIR=${HONEST_PROFILER_HOME:-$HOME/tools/honest-profiler}
    HP_LOGFILE="$PWD/honest_profiler_$(gradledev_timestamp).hpl"
    echo "Using log file ${HP_LOGFILE}"
    export LD_LIBRARY_PATH="$JAVA_HOME/jre/lib/amd64"
    gradledev_set_opts $mode "-agentpath:${HP_HOME_DIR}/liblagent.so=interval=${hp_interval},maxFrames=1024${hp_extra_properties},logPath=${HP_LOGFILE} -XX:+UnlockDiagnosticVMOptions -XX:+DebugNonSafepoints"
}

function gradledev_hp_start {
    echo start | nc 127.0.0.1 ${HP_PORT:-18080}
}

function gradledev_hp_stop {
    echo stop | nc 127.0.0.1 ${HP_PORT:-18080}
}

function gradledev_honestprofiler_gui {
    if [ -z "$HP_HOME_DIR" ]; then
        HP_HOME_DIR=${HONEST_PROFILER_HOME:-$HOME/tools/honest-profiler}
    fi
    java -cp $JAVA_HOME/lib/tools.jar:$HP_HOME_DIR/honest-profiler.jar com.insightfullogic.honest_profiler.ports.javafx.JavaFXApplication "$HP_LOGFILE"
}

function gradledev_honestprofiler_flamegraph {
    (
    if [ -z "$HP_HOME_DIR" ]; then
        HP_HOME_DIR=${HONEST_PROFILER_HOME:-$HOME/tools/honest-profiler}
    fi
    local hp_logfile="${HP_LOGFILE}"
    [ $# -lt 1 ] || hp_logfile=$1
    java -cp $JAVA_HOME/lib/tools.jar:$HP_HOME_DIR/honest-profiler.jar com.insightfullogic.honest_profiler.ports.console.FlameGraphDumperApplication "$hp_logfile" "${hp_logfile}.flames"
    cat "${hp_logfile}.flames" | grep -v ^AGCT\\. > "${hp_logfile}.flames.filtered"
    $GRADLEDEV_TOOLBOX_DIR/jfr-report-tool/flamegraph.pl "${hp_logfile}.flames.filtered" > "${hp_logfile}.svg"
    convert -size 1000x1000 -resize 1000x1000 +profile '*' "${hp_logfile}.svg" "${hp_logfile}.jpg"
    gradledev_open "${hp_logfile}.svg"
    )
}

function gradledev_profiling_target_pid {
    if [ -f gradle.pid ]; then
        cat gradle.pid
    else 
        echo `gradledev_daemon_pid`
    fi
}

function gradledev_jfr_start {
    local RECORDING_NAME="GradleDaemon"
    local DAEMON_PID
    if [ $# -eq 0 ]; then
      DAEMON_PID=`gradledev_profiling_target_pid`
    else
      DAEMON_PID=$1
      [ $# -lt 2 ] || RECORDING_NAME=$2
    fi    
    jcmd $DAEMON_PID JFR.start name=${RECORDING_NAME}_${DAEMON_PID} settings=$GRADLEDEV_TOOLBOX_DIR/etc/jfr/profiling.jfc maxsize=1G
}

function gradledev_jfr_stop {
    local RECORDING_NAME="GradleDaemon"
    local DAEMON_PID
    if [ $# -eq 0 ]; then
      DAEMON_PID=`gradledev_profiling_target_pid`
    else
      DAEMON_PID=$1
      [ $# -lt 2 ] || RECORDING_NAME=$2
    fi
    FILENAME="$PWD/${RECORDING_NAME}_${DAEMON_PID}_$(date +%F-%T).jfr"
    jcmd $DAEMON_PID JFR.stop name=${RECORDING_NAME}_${DAEMON_PID} filename=$FILENAME
    if [[ "$1" == "open" ]]; then
        jmc -open "$FILENAME" &
    else
        echo "command to open: jmc -open '$FILENAME'"
    fi
}

yjp_cli_jar="${YJP_HOME:-/opt/yjp}/lib/yjp-controller-api-redist.jar"
yjp_cli="java -jar $yjp_cli_jar localhost 10010"

function gradledev_yjp_clear {
    $yjp_cli clear-cpu-data
    $yjp_cli clear-alloc-data
    $yjp_cli clear-monitor-data
}

function gradledev_yjp_start_profiling {
    local yjp_method=sampling
    [ $# -lt 1 ] || yjp_method=$1
    case "${yjp_method}" in
        sampling)
        $yjp_cli start-cpu-sampling
        $yjp_cli start-monitor-profiling
        $yjp_cli enable-stack-telemetry
        ;;
        call_counting)
        $yjp_cli start-cpu-call-counting
        ;;
        tracing)
        $yjp_cli start-cpu-tracing
        ;;
        alloc_recording|alloc_recording_adaptive)
        $yjp_cli start-alloc-recording-adaptive
        ;;
        alloc_recording_all)
        $yjp_cli start-alloc-recording-all
        ;;
    esac
}

function gradledev_yjp_snapshot {
    $yjp_cli capture-performance-snapshot
}

function gradledev_yjp_stop_profiling {
    $yjp_cli stop-cpu-profiling
    $yjp_cli stop-alloc-recording
    $yjp_cli stop-monitor-profiling
}

function gradledev_jfr_start_idea {
    local IDEA_PID=`jps -l|grep com.intellij.idea.Main|awk '{ print $1 }'`
    [ -n "$IDEA_PID" ] && gradledev_jfr_start $IDEA_PID IDEA
}

function gradledev_jfr_stop_idea {
    local IDEA_PID=`jps -l|grep com.intellij.idea.Main|awk '{ print $1 }'`
    [ -n "$IDEA_PID" ] && gradledev_jfr_stop $IDEA_PID IDEA
}

function gradledev_jfr_start_idea_tapi {
    gradledev_jfr_start_idea
    while [ 1 ]; do
        echo "."
        if [ -f gradle.pid ]; then
            gradledev_jfr_start
            break
        fi
        sleep 1
    done
}

function gradledev_jfr_stop_idea_tapi {
    gradledev_jfr_stop_idea
    gradledev_jfr_stop
}