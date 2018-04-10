# shell functions for gradle core development
# zsh and bash are supported

if [ -z "$GRADLEDEV_TOOLBOX_DIR" ]; then
    if [ -n "$BASH_SOURCE" ];then
        GRADLEDEV_TOOLBOX_DIR=$(dirname $BASH_SOURCE)
    else
        # zsh
        GRADLEDEV_TOOLBOX_DIR=${0:a:h}
    fi
    GRADLEDEV_TOOLBOX_DIR=$(dirname $GRADLEDEV_TOOLBOX_DIR)
fi

# add bin directory to path
export PATH="$GRADLEDEV_TOOLBOX_DIR/bin:$PATH"

function gradledev_changed_modules {
    (
    local i
    local UPSTREAM="$1"
    if [ -z "$UPSTREAM" ]; then
        UPSTREAM=$(git show-upstream 2> /dev/null)
    fi
    UPSTREAM="${UPSTREAM:-origin/master}"
    for i in `git changed-files $UPSTREAM | grep subprojects | awk -F / '{ print $2 }' | sort | uniq `; do
        python -c "import sys,re; uncapitalize = lambda s: s[:1].lower() + s[1:] if s else ''; print uncapitalize(re.sub(r'(\w+)-?', lambda m:m.group(1).capitalize(), sys.argv[1]))" $i
    done
    )
}

function gradledev_changed_check_targets {
    (
    local i
    for i in `gradledev_changed_modules "$1" |grep -v docs`; do
        echo -n ":${i}:check "
        if [[ "$2" == "noit" ]]; then
            echo -n "-x :${i}:integTest "
        fi
    done
    )
}

function gradledev_run_checks {
    (
    local OPTIND OPTARG OPTERR opt additionalargs additionaltargets
    while getopts "-:" opt; do
        # long argument parsing, see http://stackoverflow.com/a/7680682
        case "${opt}" in
            -)
                case "${OPTARG}" in
                    qc)
                        additionaltargets="$additionaltargets qC"
                        ;;
                    noit)
                        additionalargs="$additionalargs noit"
                        ;;
                esac;;
        esac
    done
    shift $((OPTIND-1))
    local CHECKTARGETS="$additionaltargets $(gradledev_changed_check_targets "$1" $additionalargs)"
    if [ "$#" -gt 0 ]; then
        shift
    fi
    echo "Running ./gradlew $CHECKTARGETS $@ in `pwd`"
    ./gradlew $CHECKTARGETS "$@"
    )
}

function gradledev_setup_local_clone {
    (
    set -e
    echo "setup local clone"
    GITDIR=$(git rev-parse --show-toplevel)
    [ ! -d "$GITDIR" ] && echo "Not a git directory" && exit 1
    local UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2> /dev/null || true)
    UPSTREAM="${UPSTREAM:-origin/master}"
    CURRENTBRANCH=$(git rev-parse --abbrev-ref --symbolic-full-name HEAD)
    ORIGINNAME=$(dirname $UPSTREAM)
    ORIGINURL=$(git config --get remote.$ORIGINNAME.url)
    REPONAME=$(basename $GITDIR)
    parentdir=$(dirname $GITDIR)
    CLONEDIR="$parentdir/$REPONAME.testclone"
    cd $parentdir
    [ -d "$REPONAME.testclone" ] && echo "Clone already exists" && exit 1
    git clone -b $CURRENTBRANCH $GITDIR/.git $REPONAME.testclone
    cd $REPONAME.testclone
    git remote rename origin local
    git remote add $ORIGINNAME "$ORIGINURL"
    git fetch local
    git fetch $ORIGINNAME
    git branch --set-upstream-to $UPSTREAM
    git config receive.denyCurrentBranch ignore
    git config gc.auto 0
    echo "Clone created in `pwd`"
    cd "$GITDIR"
    git remote add testclone "$CLONEDIR/.git"
    )
}

function gradledev_cd_local_clone {
    gradledev_cd_gradle_dir
    CURRENTBRANCH=$(git rev-parse --abbrev-ref --symbolic-full-name HEAD)
    REPONAME=$(basename $PWD)
    parentdir=$(dirname $PWD)
    CLONEDIR="$parentdir/$REPONAME.testclone"
    [ ! -d "$CLONEDIR" ] && gradledev_setup_local_clone
    cd $CLONEDIR
}

function gradledev_update_local_clone {
    (
    [[ "$1" == "1" ]] || gradledev_cd_local_clone
    local UPSTREAM="$2"
    git fetch local
    local update_needed=0
    git rev-parse --verify -q $CURRENTBRANCH > /dev/null || update_needed=1
    git diff --quiet $CURRENTBRANCH local/$CURRENTBRANCH || update_needed=1
    if [ $update_needed -eq 1 ]; then
        git checkout -B $CURRENTBRANCH local/$CURRENTBRANCH
        [ -z "$UPSTREAM" ] || git branch --set-upstream-to $UPSTREAM
        exit 0
    else
        echo "No changes."
        exit 1
    fi
    )
}

function gradledev_run_checks_in_clone {
    (
    local UPSTREAM="$1"
    if [ -z "$UPSTREAM" ]; then
        UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2> /dev/null)
    else
        shift
    fi
    gradledev_cd_local_clone
    gradledev_update_local_clone 1 "$UPSTREAM" && git fetch origin
    gradledev_run_checks $UPSTREAM "$@"
    )
}

function gradledev_run_checks_continuously_in_clone {
    (
    local UPSTREAM="$1"
    if [ -z "$UPSTREAM" ]; then
        UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2> /dev/null)
    else
        shift
    fi
    gradledev_cd_local_clone
    while [ 1 ]; do
        echo "Checking for local changes"
        gradledev_update_local_clone 1 "$UPSTREAM" && git fetch origin && gradledev_run_checks $UPSTREAM "$@"
        echo "Waiting 10 seconds..."
        sleep 10
    done
    )
}

function gradledev_cd_gradle_dir {
    if [ -n "$GRADLEDEV_DIR" ]; then
        cd "$GRADLEDEV_DIR"
    else
        GITDIR=$(git rev-parse --show-toplevel)
        [ ! -d "$GITDIR" ] && echo "Not a git directory" && return 1
        cd $GITDIR
    fi
}

function gradledev_find_install {
    gradledev_find_install_dir
    [ -d $GRADLEDEV_INSTALL_DIR ] || gradledev_install
}

function gradledev_find_install_dir {
    if [ -z "$GRADLEDEV_INSTALL_DIR" ]; then
        GRADLEDEV_INSTALL_DIR=/tmp/gradle-install
    fi
}

function gradledev_use_install_dir {
    [ -f $1/bin/gradle ] || echo "Cannot find $/bin/gradle" && return 1
    GRADLEDEV_INSTALL_DIR=$1
}

function gradledev_install {
    (
    unset GRADLE_OPTS
    gradledev_cd_gradle_dir
    gradledev_find_install_dir
    ./gradlew -Pgradle_installPath=$GRADLEDEV_INSTALL_DIR install "$@"
    git rev-parse HEAD > $GRADLEDEV_INSTALL_DIR/.githash
    git rev-parse HEAD | colrm 8 > $GRADLEDEV_INSTALL_DIR/.githash_short
    )
}

function gradledev_installed_version {
    gradledev_find_install
    $GRADLEDEV_INSTALL_DIR/bin/gradle -v |egrep '^Gradle'|awk '{ print $2 }'
}

function gradledev_install_wrapper {
    (
    gradledev_install
    gradledev_find_install_dir
    echo ' ' > empty_build.gradle
    echo ' ' > empty_settings.gradle
    for (( i=0; i<2; i++ )) do
        (
        [ -z "$ZSH_VERSION" ] || { unsetopt nomatch; setopt extendedglob; }
        $GRADLEDEV_INSTALL_DIR/bin/gradle -b empty_build.gradle -c empty_settings.gradle wrapper
        GRADLE_VER=`gradledev_installed_version 2> /dev/null`
        if [[ -n "$GRADLE_VER" ]]; then
            local GRADLE_DIR="$HOME/.gradle/wrapper/dists/gradle-${GRADLE_VER}-bin/*"
            if [ -z "$ZSH_VERSION" ]; then
                GRADLE_DIR=`echo ${GRADLE_DIR}`
            else
                GRADLE_DIR=`echo ${~GRADLE_DIR}`
            fi
            cp -Rdvp $GRADLEDEV_INSTALL_DIR/. ${GRADLE_DIR}/gradle-${GRADLE_VER}
            touch ${GRADLE_DIR}/gradle-${GRADLE_VER}-bin.zip.ok
        fi
        )
    done
    rm empty_build.gradle empty_settings.gradle
    ./gradlew --version
    )
}

function gradle_cleanup_caches {
    (
    [ -z "$ZSH_VERSION" ] || unsetopt nomatch
    rm -rf ~/.gradle/caches/{1.*,2.*,3.*,4.*}
    rm -rf ~/.gradle/daemon
    rm -rf ~/.gradle/wrapper/dists/*-201*
    )
}

function javadev_gather_jstacks {
    (
    $GRADLEDEV_TOOLBOX_DIR/scripts/gather_jstacks.sh "$@"
    )
}

function gradledev_jstacks {
    javadev_gather_jstacks `jps -l |grep -i gradle|awk '{ print $1 }'`
}

function gradledev_jstacks_workers {
    javadev_gather_jstacks `jps -l |grep GradleWorkerMain|awk '{ print $1 }'`
}

function gitpush_to_forked {
  (
  CURRENTBRANCH=$(git rev-parse --abbrev-ref --symbolic-full-name HEAD)
  if [ -n "$CURRENTBRANCH" ]; then
    git push -f forked "$CURRENTBRANCH:$CURRENTBRANCH"
  fi
  )
}
