#!/bin/sh

. ../utils.sh

assert '[ `ls buum/out | wc -l` -eq 2 ]'
assert '[ -f buum/out/test.umi ]'
assert_diff test.um buum/out/test.um
