#!/bin/sh

source ./utils.sh

PASS=0
TOTAL=0

for d in */; do
  TOTAL=$(( TOTAL + 1 ))
  echo "$d" | grep -q '^f_'
  should_fail=$?
  cd $d
  [ -n "$CLEAR_CACHE" ] && rm -r buum/cache
  rm -r buum/out
  ../../../zig-out/bin/buum
  if [ "$?" -ne "$should_fail" ] && sh verify.sh; then
    PASS=$(( PASS + 1 ))
    echo "PASS $d"
    continue
  fi
  echo "FAIL $d"
done

echo $PASS out of $TOTAL passed
[ $PASS -eq $TOTAL ]
exit $?
