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

function gradledev_changed_modules {
    local i UPSTREAM
    UPSTREAM=$(git show-upstream 2> /dev/null)
    UPSTREAM="${UPSTREAM:-origin/master}"
    for i in `git changed-files $UPSTREAM | grep subprojects | awk -F / '{ print $2 }' | sort | uniq `; do 
        python -c "import sys,re; uncapitalize = lambda s: s[:1].lower() + s[1:] if s else ''; print uncapitalize(re.sub(r'(\w+)-?', lambda m:m.group(1).capitalize(), sys.argv[1]))" $i
    done
}

function gradledev_changed_check_targets {
    local i
    for i in `gradledev_changed_modules |grep -v docs`; do 
        echo -n ":${i}:check "
    done
}

function gradledev_run_checks {
    local CHECKTARGETS="$(gradledev_changed_check_targets)"
    if [[ "$1" != "--noqc" ]]; then
        CHECKTARGETS="qC $CHECKTARGETS"
    else
        shift
    fi
    echo "Running ./gradlew $CHECKTARGETS $@ in `pwd`"
    ./gradlew $CHECKTARGETS "$@"
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
    git fetch local
    local update_needed=0
    git rev-parse --verify -q $CURRENTBRANCH > /dev/null || update_needed=1
    git diff --quiet $CURRENTBRANCH local/$CURRENTBRANCH || update_needed=1
    if [ $update_needed -eq 1 ]; then
        local UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2> /dev/null || true)
        UPSTREAM="${UPSTREAM:-origin/master}"
        git checkout -B $CURRENTBRANCH local/$CURRENTBRANCH
        git branch --set-upstream-to $UPSTREAM
        exit 0
    else
        echo "No changes."
        exit 1
    fi
    )
}

function gradledev_run_checks_in_clone {
    (
    gradledev_cd_local_clone
    gradledev_update_local_clone 1 && git fetch origin
    gradledev_run_checks "$@"
    )
}

function gradledev_run_checks_continuously_in_clone {
    (
    gradledev_cd_local_clone
    while [ 1 ]; do
        echo "Checking for local changes"
        gradledev_update_local_clone 1 && git fetch origin && gradledev_run_checks "$@"
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
