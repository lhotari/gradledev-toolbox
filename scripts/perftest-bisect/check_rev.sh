#!/bin/bash
./gradlew clean
cp -Rdvp ~/.gradle-bisect-override/* .
TESTNAME=${1:-IdeIntegrationPerformanceTest}
TESTPROJECT=${2:-multi}
./gradlew -S -x :performance:prepareSamples :performance:$TESTPROJECT :performance:cleanPerformanceTest :performance:performanceTest -D:performance:performanceTest.single=$TESTNAME
result=$?
hash=$(git rev-parse HEAD | colrm 9)
datets=$(date +%Y-%m-%d-%H:%M:%S)
[ -d ~/.gradle-bisect-results ] || mkdir ~/.gradle-bisect-results
cp subprojects/performance/build/test-results/performanceTest/TEST-org.gradle.performance.$TESTNAME.xml ~/.gradle-bisect-results/result_${result}_${hash}_${datets}.xml
git reset --hard
exit $result
