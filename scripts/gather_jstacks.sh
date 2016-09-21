#!/bin/bash
if [ $# -lt 1 ]; then
    echo "Pass process ids as arguments."
    exit 1
fi
for pid in $@; do
    if [ -e "/proc/$pid" ]; then
        OWNER=$(stat -c %U /proc/$pid)
        echo "Pid $pid Owner $OWNER"
        echo "Started $(ps -p $pid --no-headers -o lstart)"
        echo "Now $(date)"
        echo "Working dir $(readlink /proc/$pid/cwd)"
        echo "Command line:"
        cat /proc/$pid/cmdline | xargs -0 -i echo {} | sed  's/^/    /'
        echo "Environment:"
        cat /proc/$pid/environ | xargs -0i echo {} | sort | sed  's/^/    /'
        ppid=$(ps -p $pid --no-headers -o ppid | awk '{ print $1 }') 
        echo "Parent process id $ppid"
        if [[ $ppid -ne 1 ]]; then
            echo "Parent Command line:"
            cat /proc/$ppid/cmdline | xargs -0 -i echo {} | sed  's/^/        /'
        fi
        JAVA_BIN=$(dirname "$(readlink /proc/$pid/exe)" | sed 's/\/jre\/bin$/\/bin/')
        JSTACK="$JAVA_BIN/jstack"
        if [ -x "$JSTACK" ]; then
                echo "Thread dump"
                sudo -u "$OWNER" $JSTACK $pid
        fi
        echo "----------------------------------------------"
    else
        echo "Pid '$pid' doesn't exist. Pass process ids as arguments."
    fi
done
