#!/bin/bash
while [ true ]; do
  ./check_rev.sh && exit 0
  git checkout HEAD~25
done
