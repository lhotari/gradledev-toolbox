function gradledev_benchmark_native_one_change {
    if [ -f modules/project5/src/src100_c.c~ ]; then
        cp modules/project5/src/src100_c.c{~,}
    else
        cp modules/project5/src/src100_c.c{,~}
    fi
    gradle_opts_jfr
    gradledev_benchmark -c 20 -j -l gradledev_benchmark_native_do_1_change "$@"
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