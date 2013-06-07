#!/usr/bin/env bash
# Launch script for a MySQLd... in a RAM disk
# Luke Carrier <luke@carrier.im>

ROOTDIR="$(dirname "$(readlink -fn "$0")")"
CONFDIR="${ROOTDIR}/conf"
RUNDIR="${ROOTDIR}/run"
PIDFILE="${RUNDIR}/mysqld.pid"
STATEDIR="${ROOTDIR}/lib"
LOGDIR="${ROOTDIR}/log"

RAMDISKSIZE=2048M

# Ensure the environment is sane
ensure_sanity() {
    if [ ! -d "${CONFDIR}" ]; then
        echo "$0: no configuration directory"
        exit
    fi

    [ -r "${CONFDIR}"/my.cnf ]
    [ -d "${LOGDIR}"   ] || mkdir -p "${LOGDIR}"
    [ -d "${RUNDIR}"   ] || mkdir -p "${RUNDIR}"
    [ -d "${STATEDIR}" ] || mkdir -p "${STATEDIR}"
    LC_ALL=C BLOCKSIZE= df --portability "${STATEDIR}"/. | tail -n 1 | awk '{ exit ($4<4096) }'

    [ -f "${PIDFILE}" ] || echo "0" >"${PIDFILE}"
}

# Create required directories
init_dirs () {
    mkdir -p \
        "${CONFDIR}" \
        "${LOGDIR}" \
        "${RUNDIR}"
}

# Initialise the RAM disk
init_ramdisk () {
    mkdir -p "${STATEDIR}"
    sudo mount -t tmpfs -o size="${RAMDISKSIZE}" tmpfs "${STATEDIR}"
    sudo chown -R "${USER}":"${USER}" "${STATEDIR}"
    mysql_install_db --defaults-file="${CONFDIR}"/my.cnf \
                     --datadir="${STATEDIR}" --user="${USER}"
}

# Delete directories
uninit_dirs () {
    rm -rf \
        "${CONFDIR}" \
        "${LOGDIR}" \
        "${RUNDIR}"
}

# Unmount the RAM disk
uninit_ramdisk () {
    sudo umount "${STATEDIR}"
    rm -rf "${STATEDIR}"
}

# Is the specified PID alive?
pid_alive () {
    if [ "$1" != "0" ] && kill -0 "$1"; then
        return 0
    fi

    return 1
}

create_db () {
    mysql -B -h127.0.0.1 -P3307 -uroot -e "CREATE DATABASE $1 CHARACTER SET utf8;"
    mysql -B -h127.0.0.1 -P3307 -uroot -e "CREATE USER \"$1\"@\"localhost\" IDENTIFIED BY \"$2\";"
    mysql -B -h127.0.0.1 -P3307 -uroot -e "GRANT ALL PRIVILEGES ON $1.* TO \"$1\"@\"localhost\";"
}

case "$1" in
    "config")
        sudo rm -rf "${CONFDIR}"
        sudo cp -r /etc/mysql "${CONFDIR}"
        sudo chown -R "${USER}":"${USER}" "${CONFDIR}"

        sed -i "s%3306%3307%g"                   "${CONFDIR}/my.cnf"
        sed -i "s%/etc/mysql%${CONFDIR}%g"       "${CONFDIR}/my.cnf"
        sed -i "s%/tmp%${TEMPDIR}%g"             "${CONFDIR}/my.cnf"
        sed -i "s%/var/lib/mysql%${STATEDIR}%g" "${CONFDIR}/my.cnf"
        sed -i "s%/var/log/mysql%${LOGDIR}%g"    "${CONFDIR}/my.cnf"
        sed -i "s%/var/run/mysqld%${RUNDIR}%g"   "${CONFDIR}/my.cnf"
        ;;

    "start")
        ensure_sanity

        pid=$(cat "${PIDFILE}")
        pid_alive "${pid}" && echo "$0: it's already running!" && exit

        init_ramdisk

        /usr/sbin/mysqld --defaults-file="${CONFDIR}"/my.cnf &>/dev/null &
        ;;

    "createdbs")
        create_db luke_tdm_le_mfa wq90tawgeuogyvasbzxfgjk
        create_db luke_tdm_le_tfa su7a0w8ta34tsdn0evoyefg
        ;;

    "stop")
        ensure_sanity

        pid=$(cat "${PIDFILE}")
        pid_alive "${pid}" && kill -9 "${pid}"

        sleep 5

        uninit_dirs
        uninit_ramdisk
        ;;

    "status")
        pid=$(cat "${PIDFILE}")
        if kill -9 "${pid}" ; then
            echo 'running'
        else
            echo 'not running'
        fi
        ;;

    *)
        echo "$0 start|stop|status"
        ;;
esac
