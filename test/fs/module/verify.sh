#!/bin/sh

. ../utils.sh

assert '[ `ls buum/out | wc -l` -eq 1 ]'
assert_diff test.um buum/out/test.um
