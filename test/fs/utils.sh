
fail () {
  rc=$?
  echo "failed: $@"
  exit rc
}

assert_diff () {
  [ -f "$1" ] || fail "file $1 doesn't exist"
  [ -f "$2" ] || fail "file $2 doesn't exist"
  diff "$1" "$2" || fail "file $1 doesn't match $2"
}

assert () {
  cmd="$1"
  eval "$cmd" || fail "$cmd"
}
