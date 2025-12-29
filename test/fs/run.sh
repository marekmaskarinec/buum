#!/bin/sh

. ./utils.sh

PASS=0
TOTAL=0

for d in */; do
  TOTAL=$(( TOTAL + 1 ))
  echo "$d" | grep -q '^f_'
  should_fail=$?
  cd $d
  [ -n "$CLEAR_CACHE" ] && rm -rf buum/cache
  rm -rf buum/out
  if [ $should_fail ]; then
    ../../../zig-out/bin/buum 2>/dev/null
  else
    ../../../zig-out/bin/buum
  fi
  if [ "$?" -ne "$should_fail" ] && sh verify.sh; then
    PASS=$(( PASS + 1 ))
    echo "PASS $d"
    cd ..
    continue
  fi
  echo "FAIL $d"
  cd ..
done

echo $PASS out of $TOTAL passed
[ $PASS -eq $TOTAL ]
exit $?
