#!/bin/sh

cat header.um >tmp
sed '/import/d' <../../src/bu.um >>tmp
cat test.um >>tmp
umka tmp
rm tmp
