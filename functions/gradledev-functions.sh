function gradledev_changed_modules {
	for i in `git changed-files $(git show-upstream) | grep subprojects | awk -F / '{ print $2 }' | sort | uniq `; do 
		python -c "import sys,re; uncapitalize = lambda s: s[:1].lower() + s[1:] if s else ''; print uncapitalize(re.sub(r'(\w+)-?', lambda m:m.group(1).capitalize(), sys.argv[1]))" $i
	done
}

function gradledev_changed_check_targets {
	for i in `gradledev_changed_modules |grep -v docs`; do 
		echo ":${i}:check"
	done
}

function gradledev_run_checks {
	CHECKTARGETS="qC $(gradledev_changed_check_targets)"
	echo "Running ./gradlew $CHECKTARGETS in `pwd`"
	./gradlew $CHECKTARGETS
}

function gradledev_setup_local_clone {
	(
	set -e
	echo "setup local clone"
	GITDIR=$(git rev-parse --show-toplevel)
	[ ! -d "$GITDIR" ] && echo "Not a git directory" && exit 1
	UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{u})
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
	GITDIR=$(git rev-parse --show-toplevel)
	[ ! -d "$GITDIR" ] && echo "Not a git directory" && exit 1
	CURRENTBRANCH=$(git rev-parse --abbrev-ref --symbolic-full-name HEAD)
	REPONAME=$(basename $GITDIR)
	parentdir=$(dirname $GITDIR)
	CLONEDIR="$parentdir/$REPONAME.testclone"
	[ ! -d "$CLONEDIR" ] && gradledev_setup_local_clone
	cd $CLONEDIR
}

function gradledev_update_local_clone {
	(
	[[ "$1" == "1" ]] || gradledev_cd_local_clone
	git fetch local
	git diff --quiet $CURRENTBRANCH local/$CURRENTBRANCH
	if [ $? -eq 1 ]; then
		git checkout -B $CURRENTBRANCH local/$CURRENTBRANCH
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
	gradledev_update_local_clone 1
	gradledev_run_checks
	)
}

function gradledev_run_checks_continuously_in_clone {
	(
	gradledev_cd_local_clone
	while [ 1 ]; do
		echo "Checking for local changes"
		gradledev_update_local_clone 1 && git fetch origin && gradledev_run_checks
		echo "Waiting 10 seconds..."
		sleep 10
	done
	)
}

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

