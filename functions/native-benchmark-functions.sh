function gradledev_benchmark_native_one_change {
    if [ -f modules/project5/src/src100_c.c~ ]; then
        cp modules/project5/src/src100_c.c{~,}
    else
        cp modules/project5/src/src100_c.c{,~}
    fi
    gradle_opts_jfr
    gradledev_benchmark -c 20 -j -l gradledev_benchmark_native_do_1_change "$@"
}

function gradledev_check_perf_test {
    (
    gradledev_install
    if [ -f modules/project5/src/src100_c.c~ ]; then
        cp modules/project5/src/src100_c.c{~,}
    else
        cp modules/project5/src/src100_c.c{,~}
    fi
    unset GRADLE_OPTS
    gradledev_benchmark -c 20 -f gradledev_check_conf_time -l gradledev_benchmark_native_do_1_change "$@"
    )
}

function gradledev_check_conf_time {
    gradledev_calc_conf_time
    [ $maxconftime -lt 750 ]
}

function gradledev_calc_conf_time {
    #avgconftime=$(cat $TIMESLOG |awk -F': ' '{ print $3 }'|awk '{ print $1 }' | awk 'NF' | tail -n +2 | awk '{ sum += $1; n++ } END { if (n > 0) print sum / n; }')
    maxconftime=$(cat $TIMESLOG |awk -F': ' '{ print $3 }'|awk '{ print $1 }' | awk 'NF' | tail -n +2 | awk '{ if ($1 > max) max=$1; } END { print max; }')
}

function gradledev_benchmark_native_do_1_change {
    ID=$(uuidgen |sed 's/-//g' |colrm 10)
    cat >> modules/project5/src/src100_c.c <<EOF
int C_function_$ID () {
  printf("Hello world!");
  return 0;
}
EOF
}