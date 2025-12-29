#!/bin/sh

. ../utils.sh

assert '[ -d buum/out/sub/dir ]'
assert '[ `ls buum/out/sub/dir | wc -l` -eq 2 ]'
assert '[ -f buum/out/sub/dir/test.umi ]'
assert_diff test.um buum/out/sub/dir/test.um
