#! /bin/sh
### BEGIN INIT INFO
# Provides:          binfmt-support
# Required-Start:    $local_fs $remote_fs
# Required-Stop:     $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:
# Short-Description: Support for extra binary formats
# Description:       Enable support for extra binary formats using the Linux
#                    kernel's binfmt_misc facility.
### END INIT INFO

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
NAME=binfmt-support
DESC="additional executable binary formats"

if [ "$(uname)" != Linux ]; then
  exit 0
fi

which update-binfmts >/dev/null 2>&1 || exit 0

. /lib/lsb/init-functions
[ -r /etc/default/rcS ] && . /etc/default/rcS

set -e
CODE=0

case "$1" in
  start)
    ADMINDIR=/var/lib/binfmts
    CACHEDIR=/var/cache/binfmts
    fmts="$(cd "$ADMINDIR"; ls)" || exit 0
    [ -z "$fmts" ] && exit 0
    log_daemon_msg "Enabling $DESC" "$NAME"
    PROCDIR=/proc/sys/fs/binfmt_misc
    if [ ! -e "$PROCDIR/register" ]; then
	if which modprobe >/dev/null 2>&1; then
	    modprobe -q binfmt_misc || true
	fi
	mount -t binfmt_misc -o nodev,noexec,nosuid binfmt_misc "$PROCDIR"
    fi
    cachefail=0
    for fmt in $fmts; do
	[ -e "$PROCDIR/$fmt" ] && continue
	if [ ! -e "$CACHEDIR/$fmt" ] ||
	   ! cat "$CACHEDIR/$fmt" > $PROCDIR/register; then
	    cachefail=1
	fi
	CODE=$?
    done
    if [ "$cachefail" = 1 ]; then
	update-binfmts --enable || CODE=$?
    fi
    log_end_msg $CODE
    exit $CODE
    ;;

  stop)
    log_daemon_msg "Disabling $DESC" "$NAME"
    update-binfmts --disable || CODE=$?
    log_end_msg $CODE
    exit $CODE
    ;;

  restart|force-reload)
    $0 stop
    $0 start
    ;;

  *)
    N=/etc/init.d/$NAME
    echo "Usage: $N {start|stop|restart|force-reload}" >&2
    exit 1
    ;;
esac

exit 0
