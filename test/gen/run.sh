#!/bin/sh -e

_=${UMKA:=umka}

cat header.um >tmp
sed '/import/d' <../../src/bu.um >>tmp
cat test.um >>tmp
$UMKA tmp
rm tmp
