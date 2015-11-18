# git-bisect script examples

All files from `~/.gradle-bisect-override` will be copied to working directory. 
Make changes to files under that directory since the script will reset any changes.

usage:
```
mkdir ~/.gradle-bisect-override
# copy test class to override directory and make changes in that directory
cp --parents  subprojects/performance/src/integTest/groovy/org/gradle/performance/IdeIntegrationPerformanceTest.groovy ~/.gradle-bisect-override
vim ~/.gradle-bisect-override/subprojects/performance/src/integTest/groovy/org/gradle/performance/IdeIntegrationPerformanceTest.groovy

# check revision
./check_rev.sh IdeIntegrationPerformanceTest multi
```

