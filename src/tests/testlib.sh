failures=0

: ${UPDATE_BINFMTS=update-binfmts}
: ${RUN_DETECTORS=run-detectors}

FAKE_PROC=false
cleanup () {
	if $FAKE_PROC && [ -e "$tmpdir/proc/register" ]; then
		fusermount -u "$tmpdir/proc"
	fi
	rm -rf "$tmpdir"
}

init () {
	tmpdir="tmp-${0##*/}"
	mkdir -p "$tmpdir" || exit $?
	trap cleanup HUP INT QUIT TERM
	mkdir -p "$tmpdir/usr/share/binfmts" "$tmpdir/var/lib/binfmts"
}

fake_proc () {
	mkdir -p "$tmpdir/proc"
	if [ "$TEST_FUSE_DEBUG" ]; then
		"$srcdir/binfmt_misc.py" -d "$tmpdir/proc" &
		sleep 1
	else
		if ! "$srcdir/binfmt_misc.py" "$tmpdir/proc" 2>/dev/null; then
			echo "SKIP: fuse unavailable"
			cleanup
			exit 77
		fi
	fi
	FAKE_PROC=:
}

update_binfmts () {
	$UPDATE_BINFMTS --admindir "$tmpdir/var/lib/binfmts" \
			--importdir "$tmpdir/usr/share/binfmts" "$@"
}

update_binfmts_proc () {
	update_binfmts --procdir "$tmpdir/proc" "$@"
}

run_detectors () {
	$RUN_DETECTORS --admindir "$tmpdir/var/lib/binfmts" \
		       --procdir "$tmpdir/proc" "$@"
}

expect_pass () {
	ret=0
	eval "$2" || ret=$?
	if [ "$ret" = 0 ]; then
		echo "  PASS: $1"
	else
		failures="$(($failures + 1))"
		echo "  FAIL: $1"
	fi
}

finish () {
	case $failures in
		0)
			cleanup
			exit 0
			;;
		*)
			if [ -z "$TEST_FAILURE_KEEP" ]; then
				cleanup
			fi
			exit 1
			;;
	esac
}
