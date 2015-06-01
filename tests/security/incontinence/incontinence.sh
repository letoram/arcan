#!/bin/sh

arcan -W headless -d :memory: -p ./ ../incontinence &> /dev/null &

sleep 1

handler(){
	PID=`cat incontinence.pid`
	rm incontinence.pid
	echo "done, killing $PID"
	kill $PID
	exit
}

trap handler INT TERM

ulimit -c unlimited

export ARCAN_CONNPATH="incontinence"
COUNTER=1
while :
do
	./incontinence
	echo " -- RUN `date` -- " >> incontinence.log
	PID=`cat incontinence.pid`
	cat /proc/$PID/maps >> incontinence.log
	echo "`cat /proc/$PID/maps |wc -l` mappings "
	ls -l /proc/$PID/fd >> incontinence.log
	echo "`ls -l /proc/$PID/fd |wc -l` files "
	ls -l /dev/shm/ |grep arcan >> incontinence.log
	echo "`ls -l /dev/shm | grep arcan | wc -l` shared entries"
	if [ -e core ] ; then
		mv core core.$COUNTER
	fi
done
