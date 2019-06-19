#!/usr/bin/ksh
#Auth 		: MX
#Purpose 	: Do VM disk mapping 
#Dependency  	: all.storage.pl in ${workdir}
#Input File   	: luns in ${workdir}
#Input File Format 
#	<STORAGEID>    <LUNID> 
#	CKM001337xxxxx 1968
#	CKM001337xxxxx  1966
#	CKM001337xxxxx  1967
#Ver 	: 4.0
#Update : Single call of hpvmmodify to save time.
#Update : Exits if NOT all disks are detected
#Update : ioscan and powermt can be performed by giving [Y|y] as second argument .
#Update : Adding color to the messages
#Update : Fix for duplicate disk issue
#usage  : imap.ksh <VM Name> [Y|y] 


workdir="/var/tmp/mx"
MYVM=$1
DISKFOUND=0
typeset -u SCAN 
SCAN='N'
RED='\033[31m'
GREEN='\033[32m'
NOCOLOR='\033[00m'

function msg {
	printf  $GREEN
	echo "$*"
	printf $NOCOLOR
}

function err {
	printf $RED
	echo "$*"
	printf $NOCOLOR
}
 
 
function save {
	if [ -f $1 ]
	then
		mv $1 $1.$$
	fi
}

function scan {

	powermt display > pout.before.$$
	powermt display dev=all > pout.all.before.$$
	msg "Running ioscan "
	ioscan -fn >/dev/null
	ioscan -fnC disk >/dev/null
	ioscan -m dsf > /dev/null
	msg "Running insf "
	insf   > /dev/null
	insf  -C disk > /dev/null
	save pout
	save pout.all
	msg "Removing NO_HW paths, if any"
	for NOHWPATHS  in $(ioscan -fNC lunpath| awk '/NO_HW/{print $2}')
	do
		scsimgr -f replace_wwid -C lunpath -I $NOHWPATHS
	done

	msg "Running powermt config "
	powermt config
	msg "Running powermt save "
	powermt save
	msg "Running powermt check "
	msg "************************************************"
	powermt check
	powermt display > pout
	powermt display dev=all > pout.all
}


#Exit if NOT root
if [ $(whoami) != "root" ]  
then 
	err  "ERROR 10 : You must run as root"  
	exit 10  
fi

if [ ! -f /opt/hpvm/bin/hpvmstatus ]
then
        err "ERROR 8 : This script meant to be run on IVM Host"
        exit 8
fi

#Exit if VM Name is not supplied
if [ $# -lt 1 ]   
then 
	err "ERROR 9 : USAGE is $(basename $0 ) <VM Name>  [Y|y] "  
	exit 9  
elif [ $# -gt 1 ]  
then 
	SCAN=$2
fi

if [ !  -d ${workdir}/${MYVM} ] ; then mkdir ${workdir}/${MYVM}  ;  fi

if [ -d ${workdir}/${MYVM} ] ; then cd ${workdir}/${MYVM} ; else exit 10 ;  fi

if [ $SCAN = "Y" ] ; then 
	scan
else
	powermt display dev=all > pout.all
fi

save lun-to-disk
save disks
save do.disk.${MYVM}.ksh
save del.disk.${MYVM}.ksh

if [ -f ${workdir}/all.storage.pl ] && [ -x ${workdir}/all.storage.pl ]  
then 
	echo
	${workdir}/all.storage.pl > lun-to-disk
else 
	err "ERROR 11 :Please Copy ${workdir}/all.storage.pl from xxxxxx:/var/tmp/mx \nThen set execute permission " 
	exit 11 
fi


if [ -f ${workdir}/luns ]  && [ ! -z ${workdir}/luns ] 
then
	cp -p  ${workdir}/luns 	${workdir}/${MYVM}/luns
	cat  luns | while read storage luns
        do echo "$luns :$(awk -v LUN=$luns] '$6==LUN {print $0}' < lun-to-disk | grep -iw $storage)"  >> disks
		if [ $(awk -v LUN=$luns] '$6==LUN {print $0}' < lun-to-disk | grep -icw $storage) = 1 ]
		then 
			DISKFOUND=$( expr $DISKFOUND + 1 )
		else 
			print "$luns NOT FOUND"
		fi
        done

	#STOP processing if NOT ALL disks are identified
	LUNFOUND=$(wc -l ${workdir}/${MYVM}/luns | cut -d " " -f 1 )
	print
	print "$DISKFOUND disks found \n "
	
	if [ $LUNFOUND  != $DISKFOUND ]
	then
		err "Luns  in ${workdir}/${MYVM}/luns :  $LUNFOUND"
		err "Disks in ${workdir}/${MYVM}/disks : $DISKFOUND"
		err "ERROR 12 : Please check and configure disks . Then rerun the $(basename $0)"
		exit 12 ;
	fi


	awk -v VMNAME=$MYVM 'BEGIN { 
                printf ("hpvmmodify -P %s ", VMNAME );
        	}
        	{
                	printf (" -a disk:avio_stor::disk:/dev/rdisk/%s ",$8 );
        	} END {
  			printf ("\n") ; 
		} ' < disks | \
		tee do.disk.${MYVM}.ksh
	#Now generate delete commands for easy undo. 
	awk -F "-a" '{ 
		for(i=2;i<=NF;i++) { 
			printf ("%s -d %s\n",$1,$i);
		}
	}' < do.disk.${MYVM}.ksh > del.disk.${MYVM}.ksh
	
	print
	printf "No mapping performed. Please run "
	msg "ksh ./${MYVM}/do.disk.${MYVM}.ksh"
	#printf "to do mapping \n"
	mv ${workdir}/luns ${workdir}/luns.${MYVM}.processed.$$
else
	err "ERROR 13 : LUN information file not present or empty : ${workdir}/luns"
	exit 13 ;
fi
