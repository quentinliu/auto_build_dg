#!/bin/bash
###############################################
# Name:generate_auto_fullbackup.sh
# Author:cdshrewd (cdshrewd#163.com)
# Purpose:Auto build dataguard for 11.2.0.x single instance on Linux Platform.
# Usage:It should be run by root.You can run it like this:
# You must provide at least 3 params.The params pri_db_name, pri_backup_dir and std_host_ip are required. 
# You can use this script likes: "./auto_build_dg_by_cdshrewd.sh -pri_db_name 'oradb' \
# -pri_backup_dir '/u01/app/backup' \
# -std_host_ip '192.168.x.x' \
# -pri_sys_password 'oracle' \
# -std_backup_dir '/u01/app/backup_tgt' \
# -run_backup_now 'yes' \
# -std_db_name 'oradbdg' -target_data_dir '/oradata/'
#  This script will create shell file in current direcory.
#  You should make these directories avaliable.
# Modified Date:2017/08/23
###############################################
#set -x
BASEPATH=$(cd `dirname $0`; pwd)
RUN_BACKUP_NOW="no"
SSH_CONNECTIVITY="no"
RMAN_LOGFILE_NAME=""
RMAN_BACKUP_TAG="AUTO_FULLBACKUP_BY_CDSHREWD"
RMAN_STD_CONTROL_NAME="auto_stdcontrol_by_cdshrewd.ctl"
RMAN_FILE_CHECK_INTERVAL=5
RMAN_LOG_PREFIX="auto_fullbackup_cds_"
RMAN_LOG_SUFFIX=".out"
PRI_ORCL_USER=`ps -ef|grep ora_smon|grep -v grep|head -1|awk '{print $1}'`
LOG_ARCHIVE_DEST="log_archive_dest_2"
LOG_ARCHIVE_ATTR=" LGWR ASYNC "
CLEAN_STAGE_FILE="yes"
echo "primary db runs by $PRI_ORCL_USER"
PRI_ORCL_USER_HOME=`grep ^$PRI_ORCL_USER /etc/passwd|awk -F ':' '{print $6}'`
. $PRI_ORCL_USER_HOME/.bash_profile
echo "primary db user home is :$PRI_ORCL_USER_HOME"
USERID=`id -u $PRI_ORCL_USER`
# PRI_DB_UNIQUE_NAME=`ps -ef|grep ora_smon|grep -v grep|awk '{print $8}'|awk -F '_' '{print $3}'`
echo "primary db runs by $USERID"
echo "params count $#"
if [ $# -lt 3 ]; then
	echo "You must provide at least 3 params.The params pri_db_name, pri_backup_dir and std_host_ip are required. "
	echo "You can use this script likes: \"$0 -pri_db_name 'oradb' \\"
	echo " -pri_backup_dir '/u01/app/backup' \\"
	echo " -std_host_ip '192.168.x.x' \\"
	echo " -pri_sys_password 'oracle' \\"
	echo " -std_backup_dir '/u01/app/backup_tgt' \\"
        echo " -run_backup_now 'yes' \\"
	echo " -std_db_name 'oradbdg' -target_data_dir '/oradata/'"
        exit 1
fi

while [ $# -gt 0 ]
  do
    case $1 in
      -std_host_ip) shift;STD_HOST_IP=$1;;         #  std_host_ip is set 
      -pri_db_name) shift;PRI_DB_UNIQUE_NAME=$1;;         #  primary db_unique_name is set 
      -pri_sys_password) shift;PRI_SYS_PASSWORD=$1;;         #  primary db_unique_name is set 
      -pri_backup_dir) shift; PRI_BACKUP_DIR='/u01/app/backup'; export PRI_BACKUP_DIR;;  # PRI_BACKUP_DIR is set
      -std_backup_dir) shift; STD_BACKUP_DIR=$1; export STD_BACKUP_DIR;;  # STD_BACKUP_DIR is set
      -run_backup_now) shift;RUN_BACKUP_NOW=$1;export RUN_BACKUP_NOW;;
      -std_db_name) shift; STD_DB_UNIQUE_NAME=$1; export STD_DB_UNIQUE_NAME;;
      -target_data_dir) shift; TARGET_DATA_DIR=$1; export TARGET_DATA_DIR;;
    esac;
    shift
  done

ORACLE_SID=$PRI_DB_UNIQUE_NAME
ORACLE_HOME=`grep -v "#" /etc/oratab|grep $ORACLE_SID|awk -F: '{print $2}'`
PRI_HOST_IP=`/sbin/ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|head -1|awk '{print $2}'|tr -d "addr:"`
REMOTE_ORACLE_HOME=$ORACLE_HOME
echo $ORACLE_HOME";sid:"$ORACLE_SID
echo $ORACLE_HOME/dbs/orapw$PRI_DB_UNIQUE_NAME
echo "PRI_HOST_IP:"$PRI_HOST_IP
# get sys password
while true
do
if [ -z "$PRI_SYS_PASSWORD" -a ! -f "$ORACLE_HOME/dbs/orapw$PRI_DB_UNIQUE_NAME" ]; then 
         read -p "pls input sys password:" PRI_SYS_PASSWORD
        if [ -n "$PRI_SYS_PASSWORD" ]; then
	break
	fi
else
	break
fi
done

if [ -z "$STD_HOST_IP" -o -z "$PRI_DB_UNIQUE_NAME" -o -z "$PRI_BACKUP_DIR" ]; then
echo "You must provide at least 3 params.The params pri_db_name, pri_backup_dir and std_host_ip are required. "
RUNNING_INSTS=`ps -ef|grep ora_smon|grep -v grep|awk '{print $8}'|awk -F '_' '{print $3}'`
if [ -z "$PRI_DB_UNIQUE_NAME" ]; then
echo "$RUNNING_INSTS are(is) running on the host.Pls check the right databse for pri_db_name." 
fi
exit 1
fi

if [ -z "$STD_DB_UNIQUE_NAME" ]; then
	STD_DB_UNIQUE_NAME=$PRI_DB_UNIQUE_NAME"dg"
fi


if [ -z "$STD_BACKUP_DIR" ]; then
        STD_BACKUP_DIR=$PRI_BACKUP_DIR
fi

if [ -n "$STD_HOST_IP" ]; then
ping $STD_HOST_IP -c1
if [ ! $? -eq 0 ]; then
echo "The host $STD_HOST_IP is unreachable.Pls check the value for parameter std_host_ip."
exit 1
else
 ssh -o NumberOfPasswordPrompts=0 -o StrictHostKeyChecking=no  $STD_HOST_IP "date"
 if [ ! $? -eq 0 ]; then
  ssh $STD_HOST_IP mv /root/.shh /root/.ssh_by_cdshrewd
  ${BASEPATH}/sshUserSetup.sh -user root -hosts $STD_HOST_IP
  if [ $? -eq 0 ]; then
     SSH_CONNECTIVITY="yes"
  fi
 else
  echo "ssh equal is ok!"
  SSH_CONNECTIVITY="yes"
 fi
fi
fi
echo "STD_HOST_IP:$STD_HOST_IP"
echo "PRI_DB_UNIQUE_NAME:$PRI_DB_UNIQUE_NAME"
echo "PRI_SYS_PASSWORD:$PRI_SYS_PASSWORD"
echo "PRI_BACKUP_DIR:$PRI_BACKUP_DIR"
echo "STD_BACKUP_DIR:$STD_BACKUP_DIR"
echo "STD_DB_UNIQUE_NAME:$STD_DB_UNIQUE_NAME"
echo "RUN_BACKUP_NOW:$RUN_BACKUP_NOW"
echo "TARGET_DATA_DIR:$TARGET_DATA_DIR"
# create pfile
create_pfile()
{
USERNAME=$PRI_ORCL_USER
MGRP=`id -ng $PRI_ORCL_USER`
export ORACLE_SID=$PRI_DB_UNIQUE_NAME
export ORACLE_DGSID=$STD_DB_UNIQUE_NAME
dgpfile_name="/tmp/init$ORACLE_DGSID.ora"
echo $dgpfile_name
dgpfile_bak_name=$dgpfile_name".bak"
echo $dgpfile_bak_name
date_str=`date +%Y%m%d`
pfile_name=""
pfile_name="/tmp/"$date_str"_cdshrewd.ora"
pfile_bak_name=$pfile_name".bak"
if [ -n $pfile_name -a -e $pfile_name ]; then
mv $pfile_name $pfile_bak_name
fi

if [ -n $dgpfile_name -a -e $dgpfile_name ]; then
mv $dgpfile_name $dgpfile_bak_name
fi
ORACLE_SID=$PRI_DB_UNIQUE_NAME
ORACLE_DGSID=$STD_DB_UNIQUE_NAME
sqlplus -S / as sysdba <<EOF
set feedback off
set term off
col v_filename new_value v_filename noprint
Select to_char(sysdate,'yyyymmdd')||'_cdshrewd' v_filename from dual;
create pfile='/tmp/&v_filename\.ora' from spfile;
# alter database force logging;
alter system switch logfile;
exit
EOF
grep -v "$ORACLE_SID.__" $pfile_name|grep -v -i "db_unique_name" > $dgpfile_name
sed -i "s/$ORACLE_SID/$ORACLE_DGSID/g" $dgpfile_name 
sed -i "s/db_name='$ORACLE_DGSID'/db_name='$ORACLE_SID'/g" $dgpfile_name
echo "*.db_unique_name='$ORACLE_DGSID'" >> $dgpfile_name
mv $dgpfile_name $PRI_BACKUP_DIR/
}

create_pfile

# create target dirs
create_tgt_dirs()
{
CREATE_DIRS_FILE=$PRI_BACKUP_DIR/auto_create_dirs_by_cdshrewd.sh
echo "#!/bin/bash" > $CREATE_DIRS_FILE
echo "ORACLE_DGSID=$STD_DB_UNIQUE_NAME" >> $CREATE_DIRS_FILE
echo "dgpfile_name=$STD_BACKUP_DIR/init$ORACLE_DGSID.ora" >> $CREATE_DIRS_FILE
echo "for dest in \`grep dest \$dgpfile_name |grep -v \"size\"|awk -F= '{print \$NF}'|sed \"s/'//g\"\`" >> $CREATE_DIRS_FILE
echo "do" >> $CREATE_DIRS_FILE
echo "if [ ! -e \$dest ]; then" >> $CREATE_DIRS_FILE
echo "mkdir -p \$dest" >> $CREATE_DIRS_FILE
echo "chown -R $USERNAME:$MGRP \$dest" >> $CREATE_DIRS_FILE
echo "echo \"create dir \$dest\"" >> $CREATE_DIRS_FILE
echo "fi" >> $CREATE_DIRS_FILE
echo "done" >> $CREATE_DIRS_FILE
echo "if [ ! -e $TARGET_DATA_DIR ]; then " >> $CREATE_DIRS_FILE
echo "mkdir -p $TARGET_DATA_DIR" >> $CREATE_DIRS_FILE
echo "chown -R $USERNAME:$MGRP $TARGET_DATA_DIR" >> $CREATE_DIRS_FILE
echo "echo \"create dir $TARGET_DATA_DIR\"" >> $CREATE_DIRS_FILE
echo "fi" >> $CREATE_DIRS_FILE
scp $CREATE_DIRS_FILE $STD_HOST_IP:$STD_BACKUP_DIR/
ssh $STD_HOST_IP chmod a+x $STD_BACKUP_DIR/auto_create_dirs_by_cdshrewd.sh
}
create_tgt_dirs

create_pwdfile()
{
USERNAME=$PRI_ORCL_USER
MGRP=`id -ng $PRI_ORCL_USER`
export ORACLE_SID=$PRI_DB_UNIQUE_NAME
export ORACLE_DGSID=$STD_DB_UNIQUE_NAME
echo $USERNAME
echo "group:"$MGRP

ORACLE_SID=$PRI_DB_UNIQUE_NAME
ORACLE_DGSID=$STD_DB_UNIQUE_NAME
date_str=`date +%Y%m%d%H%M`
if [ -f $ORACLE_HOME/dbs/orapw$ORACLE_SID ]; then
mv $ORACLE_HOME/dbs/orapw$ORACLE_SID $ORACLE_HOME/dbs/orapw$ORACLE_SID.$date_str
fi
echo "SID:"$ORACLE_SID
echo "DGSID:"$ORACLE_DGSID
echo "orapwd file=$ORACLE_HOME/dbs/orapw$ORACLE_SID password=$PRI_SYS_PASSWORD ignorecase=y force=y entries=10"
orapwd file=$ORACLE_HOME/dbs/orapw$ORACLE_SID password=$PRI_SYS_PASSWORD ignorecase=y force=y entries=10 format=12
cp $ORACLE_HOME/dbs/orapw$ORACLE_SID $PRI_BACKUP_DIR/orapw$ORACLE_DGSID
}
if [ -n "$PRI_SYS_PASSWORD" ]; then
{
create_pwdfile
}
fi

get_lsnr_port()
{
. $PRI_ORCL_USER_HOME/.bash_profile
ora_ports="1521"
LSNRCTL="$ORACLE_HOME/bin/lsnrctl"
for lsnr in `ps -ef|grep lsnr|egrep -v 'grep|LISTENER_SCAN1' |awk '{print $9}'`
do
	tmp_ports=`lsnrctl status $lsnr|egrep -B20 $PRI_DB_UNIQUE_NAME|grep DESCRIPTION|grep PORT=|awk -F= '{print $6}'|awk -F')' '{print $1}'|uniq`
        if [ -n "$tmp_ports" ]; then
	ora_ports=$tmp_ports
        fi
done
echo $ora_ports
}

create_tnsfile()
{
ORACLE_PORT=`get_lsnr_port`
. $PRI_ORCL_USER_HOME/.bash_profile
USERNAME=$PRI_ORCL_USER
MGRP=`id -ng $PRI_ORCL_USER`
date_str=`date +%Y%m%d%H%M`
export TNS_BAK_FILE=$ORACLE_HOME/network/admin/tnsnames.ora.$date_str
echo $TNS_BAK_FILE
PRI_HOST_NAME=`hostname`
PRI_TMP_TNS_FILE=$PRI_BACKUP_DIR/auto_pri_tnsnames.ora.cdshrewd.tmp
STD_TMP_TNS_FILE=$PRI_BACKUP_DIR/auto_std_tnsnames.ora.cdshrewd.tmp
ORACLE_SID=$PRI_DB_UNIQUE_NAME
ORACLE_DGSID=$STD_DB_UNIQUE_NAME
if [ -f "$ORACLE_HOME/network/admin/tnsnames.ora" ]; then
mv $ORACLE_HOME/network/admin/tnsnames.ora $TNS_BAK_FILE
fi
echo "$PRI_DB_UNIQUE_NAME =" > $PRI_TMP_TNS_FILE
echo "  (DESCRIPTION =" >> $PRI_TMP_TNS_FILE
echo "    (ADDRESS = (PROTOCOL = TCP)(HOST = $PRI_HOST_IP)(PORT = $ORACLE_PORT))" >> $PRI_TMP_TNS_FILE
echo "   (CONNECT_DATA =" >> $PRI_TMP_TNS_FILE
echo "      (SERVER = DEDICATED)" >> $PRI_TMP_TNS_FILE
echo "      (SERVICE_NAME = $ORACLE_SID)" >> $PRI_TMP_TNS_FILE
echo "    )" >> $PRI_TMP_TNS_FILE
echo "  )" >> $PRI_TMP_TNS_FILE
echo "" >> $PRI_TMP_TNS_FILE

echo "$STD_DB_UNIQUE_NAME =" > $STD_TMP_TNS_FILE
echo "  (DESCRIPTION =" >> $STD_TMP_TNS_FILE
echo "    (ADDRESS = (PROTOCOL = TCP)(HOST = $STD_HOST_IP)(PORT = $ORACLE_PORT))" >> $STD_TMP_TNS_FILE
echo "   (CONNECT_DATA =" >> $STD_TMP_TNS_FILE
echo "      (SERVER = DEDICATED)" >> $STD_TMP_TNS_FILE
echo "      (SERVICE_NAME = $ORACLE_DGSID)" >> $STD_TMP_TNS_FILE
echo "    )" >> $STD_TMP_TNS_FILE
echo "  )" >> $STD_TMP_TNS_FILE
echo "" >> $STD_TMP_TNS_FILE
cat $PRI_TMP_TNS_FILE
cat $STD_TMP_TNS_FILE
PRI_TNS=`egrep -A10 "^$PRI_DB_UNIQUE_NAME" $TNS_BAK_FILE|egrep -A5 "HOST = ${PRI_HOST_NAME}|HOST = $PRI_HOST_IP"|grep "SERVICE_NAME"|grep "$ORACLE_SID)"`
echo "$PRI_TNS"
echo "# modified by cdshrewd at $date_str" > $ORACLE_HOME/network/admin/tnsnames.ora
if [ x"$PRI_TNS" == x ]; then
echo "add pri tns"
cat $PRI_TMP_TNS_FILE >> $ORACLE_HOME/network/admin/tnsnames.ora
fi
STD_TNS=`egrep -A10 "^$STD_DB_UNIQUE_NAME" $TNS_BAK_FILE|egrep -A5 "HOST = $STD_HOST_IP"|grep "SERVICE_NAME"|grep "$ORACLE_DGSID)"`
echo "$STD_TNS"
if [ x"$STD_TNS" == x ]; then
echo "add std tns"
cat $STD_TMP_TNS_FILE >> $ORACLE_HOME/network/admin/tnsnames.ora
fi
echo "before create new tnsnames:"$TNS_BAK_FILE
grep -v "#" $TNS_BAK_FILE >> $ORACLE_HOME/network/admin/tnsnames.ora 
chown $USERNAME:$MGRP $ORACLE_HOME/network/admin/tnsnames.ora
cat $PRI_TMP_TNS_FILE $STD_TMP_TNS_FILE > $PRI_BACKUP_DIR/auto_tnsnames_by_cdshrewd.${ORACLE_DGSID}.tmp
}
create_tnsfile

# change primary parameters
change_pri_parameter()
{
USERNAME=$PRI_ORCL_USER
MGRP=`id -ng $PRI_ORCL_USER`
export ORACLE_SID=$PRI_DB_UNIQUE_NAME
CHNAGE_PARAMETER_SQL=$PRI_BACKUP_DIR/auto_pri_change_parameters_by_cdshrewd.sh
echo "" > $CHNAGE_PARAMETER_SQL
echo "ORACLE_SID=$PRI_DB_UNIQUE_NAME" >> $CHNAGE_PARAMETER_SQL
echo "sqlplus -S / as sysdba  <<EOF" >> $CHNAGE_PARAMETER_SQL
echo "alter system set log_archive_config='dg_config=($PRI_DB_UNIQUE_NAME,$STD_DB_UNIQUE_NAME)';" >> $CHNAGE_PARAMETER_SQL
echo "alter system set $LOG_ARCHIVE_DEST='service=$STD_DB_UNIQUE_NAME $LOG_ARCHIVE_ATTR valid_for=(online_logfiles,primary_role) db_unique_name=$STD_DB_UNIQUE_NAME';" >> $CHNAGE_PARAMETER_SQL
echo "alter system set fal_server='$STD_DB_UNIQUE_NAME';" >> $CHNAGE_PARAMETER_SQL
echo "alter system set fal_client='$PRI_DB_UNIQUE_NAME';" >> $CHNAGE_PARAMETER_SQL
echo "alter system set standby_file_management='auto';" >> $CHNAGE_PARAMETER_SQL
echo "alter system switch logfile;" >> $CHNAGE_PARAMETER_SQL
echo "alter database force logging;" >> $CHNAGE_PARAMETER_SQL
echo "exit" >> $CHNAGE_PARAMETER_SQL
echo "EOF" >> $CHNAGE_PARAMETER_SQL
chmod a+x $CHNAGE_PARAMETER_SQL
$CHNAGE_PARAMETER_SQL
}
change_pri_parameter

# change standby parameters
change_std_parameter()
{
USERNAME=$PRI_ORCL_USER
MGRP=`id -ng $PRI_ORCL_USER`
export ORACLE_SID=$STD_DB_UNIQUE_NAME
CHNAGE_PARAMETER_SQL=$PRI_BACKUP_DIR/auto_std_change_param_by_cdshrewd.sh
echo "export ORACLE_SID=$STD_DB_UNIQUE_NAME" > $CHNAGE_PARAMETER_SQL
echo "export ORACLE_HOME=$REMOTE_ORACLE_HOME" >> $CHNAGE_PARAMETER_SQL
echo "export PATH=$PATH:$ORACLE_HOME/bin" >> $CHNAGE_PARAMETER_SQL
echo "ORACLE_SID=$STD_DB_UNIQUE_NAME" >> $CHNAGE_PARAMETER_SQL
echo "sqlplus -S / as sysdba  <<EOF" >> $CHNAGE_PARAMETER_SQL
echo "startup nomount;" >> $CHNAGE_PARAMETER_SQL
echo "alter system set log_archive_config='dg_config=($PRI_DB_UNIQUE_NAME,$STD_DB_UNIQUE_NAME)';" >> $CHNAGE_PARAMETER_SQL
echo "alter system set $LOG_ARCHIVE_DEST='service=$PRI_DB_UNIQUE_NAME $LOG_ARCHIVE_ATTR valid_for=(online_logfiles,primary_role) db_unique_name=$PRI_DB_UNIQUE_NAME';" >> $CHNAGE_PARAMETER_SQL
echo "alter system set fal_server='$PRI_DB_UNIQUE_NAME';" >> $CHNAGE_PARAMETER_SQL
echo "alter system set fal_client='$STD_DB_UNIQUE_NAME';" >> $CHNAGE_PARAMETER_SQL
echo "alter system set standby_file_management='auto';" >> $CHNAGE_PARAMETER_SQL
echo "exit" >> $CHNAGE_PARAMETER_SQL
echo "EOF" >> $CHNAGE_PARAMETER_SQL
}
change_std_parameter
# split strings into array
split()
{
a=$1
OLD_IFS="$IFS"
IFS=$2
if [ -z $IFS ]; then
IFS=" "
fi
arr=($a)
IFS="$OLD_IFS"
for s in ${arr[@]}
do
    echo "$s"
done
}

get_remote_ora_home()
{
REMOTE_HOST=$1
LOCAL_VERSION=$2
ORA_INV=`ssh $REMOTE_HOST cat /etc/oraInst.loc |grep inventory_loc|awk -F= '{print $NF}'`
INVENTORY_FILE=`find $ORA_INV -name "inventory.xml"|grep -v backup`
ORA_HOME_TEMP=""
for ora_home in `ssh $REMOTE_HOST egrep  '\<HOME'  $INVENTORY_FILE|egrep 'TYPE="O"'|grep 'LOC='|gawk -F"LOC=" '{print $NF}'|awk  '{print  $1}'`
do
ora_home=${ora_home:1:${#ora_home}-2}
ssh $REMOTE_HOST ls -l $ora_home/bin/sqlplus >/dev/null
if [ $? -eq 0 ]; then
echo "">/tmp/check_sqlplus_v.sh
echo "export ORACLE_HOME=$ora_home" >> /tmp/check_sqlplus_v.sh
echo "export PATH=$ora_home/bin:\$PATH" >> /tmp/check_sqlplus_v.sh
echo " if [ -x ${ora_home}/bin/sqlplus ]; then" >> /tmp/check_sqlplus_v.sh
echo "echo \`sqlplus -v|grep SQL\`">>/tmp/check_sqlplus_v.sh
echo "fi" >> /tmp/check_sqlplus_v.sh
echo "exit" >>/tmp/check_sqlplus_v.sh
scp /tmp/check_sqlplus_v.sh $REMOTE_HOST:/tmp/
ssh $REMOTE_HOST chmod a+x /tmp/check_sqlplus_v.sh
ver=`ssh $REMOTE_HOST /tmp/check_sqlplus_v.sh`
if [ "$ver" == "$LOCAL_VERSION" ]; then
ORA_HOME_TEMP=$ora_home
ssh $REMOTE_HOST rm -f /tmp/check_sqlplus_v.sh
break
fi
fi
done
echo $ORA_HOME_TEMP
}

PRI_ORCL_USER=`ps -ef|grep ora_smon|grep -v grep|head -1|awk '{print $1}'`
PRI_ORCL_USER_HOME=`grep ^$PRI_ORCL_USER /etc/passwd|awk -F ':' '{print $6}'`
LOCAL_VERSION=`sqlplus -v|grep SQL`
echo "$LOCAL_VERSION"
REMOTE_ORACLE_HOME=`get_remote_ora_home $STD_HOST_IP "$LOCAL_VERSION"`
echo $REMOTE_ORACLE_HOME


# create remote listener
create_remote_listener()
{
USERNAME=$PRI_ORCL_USER
MGRP=`id -ng $PRI_ORCL_USER`
export ORACLE_SID=$PRI_DB_UNIQUE_NAME
STD_LISTENER=$PRI_BACKUP_DIR/listener.ora
echo "LISTENER ="> $STD_LISTENER
echo "  (DESCRIPTION_LIST =">> $STD_LISTENER
echo "    (DESCRIPTION =">> $STD_LISTENER
echo "      (ADDRESS = (PROTOCOL = TCP)(HOST = $STD_HOST_IP)(PORT = 1521))">> $STD_LISTENER
echo "	      (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1521))">> $STD_LISTENER
echo "	    )">> $STD_LISTENER
echo "	  )">> $STD_LISTENER
echo "	">> $STD_LISTENER
echo "	">> $STD_LISTENER
echo "SID_LIST_LISTENER =    ">> $STD_LISTENER
echo "	(SID_LIST =    ">> $STD_LISTENER
echo "	    (SID_DESC =    ">> $STD_LISTENER
echo "	      (SID_NAME = PLSExtProc)   ">> $STD_LISTENER 
echo "	      (ORACLE_HOME = $REMOTE_ORACLE_HOME) ">> $STD_LISTENER   
echo "	      (PROGRAM = extproc)    ">> $STD_LISTENER
echo "	    )    ">> $STD_LISTENER
echo "	    ">> $STD_LISTENER
echo "	    (SID_DESC =    ">> $STD_LISTENER
echo "	      (GLOBAL_DBNAME = $STD_DB_UNIQUE_NAME)    ">> $STD_LISTENER
echo "	      (ORACLE_HOME =  $REMOTE_ORACLE_HOME)  ">> $STD_LISTENER  
echo "	      (SID_NAME = $STD_DB_UNIQUE_NAME)    ">> $STD_LISTENER
echo "	    )    ">> $STD_LISTENER
echo "	    ">> $STD_LISTENER
echo "	)   ">> $STD_LISTENER

REMOTE_LISTENER_DIR=${REMOTE_ORACLE_HOME}/network/admin/listener.ora

scp $STD_LISTENER $STD_HOST_IP:$REMOTE_LISTENER_DIR
}
create_remote_listener


generate_startup_instance()
{
echo "export ORACLE_SID=$STD_DB_UNIQUE_NAME" > $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "export ORACLE_HOME=$REMOTE_ORACLE_HOME" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "export PATH=$PATH:$ORACLE_HOME/bin" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "USERNAME=$PRI_ORCL_USER" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "lsnrctl start" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "INST_EXISTS=\`ps -ef|grep ora_smon_$STD_DB_UNIQUE_NAME|grep -v grep\`" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "if [ x"\$INST_EXISTS" = x ]; then" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "export ORACLE_SID=$STD_DB_UNIQUE_NAME" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "sqlplus -S / as sysdba <<EOF" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "startup nomount pfile='$STD_BACKUP_DIR/init$STD_DB_UNIQUE_NAME.ora';" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "create spfile from pfile;" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "shutdown abort;">> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "exit" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "EOF" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "export ORACLE_SID=$STD_DB_UNIQUE_NAME" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "sqlplus -S / as sysdba <<EOF" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "startup nomount;" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "exit" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "EOF" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "else" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "echo \"instance $STD_DB_UNIQUE_NAME exists.\"" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
echo "fi" >> $PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh

AUTO_START_STD=$PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
#scp $AUTO_START_STD $STD_HOST_IP:$STD_BACKUP_DIR
ssh $STD_HOST_IP chmod a+x $STD_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
}
generate_startup_instance

generate_restore_scripts()
{
echo "rman target sys/$PRI_SYS_PASSWORD@$PRI_DB_UNIQUE_NAME auxiliary sys/$PRI_SYS_PASSWORD@$STD_DB_UNIQUE_NAME nocatalog <<RMAN" > $PRI_BACKUP_DIR/duplicate_database.sh
echo "duplicate target database for standby from active database nofilenamecheck;" >> $PRI_BACKUP_DIR/duplicate_database.sh
echo "exit" >> $PRI_BACKUP_DIR/duplicate_database.sh
echo "RMAN" >> $PRI_BACKUP_DIR/duplicate_database.sh
chmod a+x $PRI_BACKUP_DIR/duplicate_database.sh

}
generate_restore_scripts

transfer_files()
{
  if [[ $SSH_CONNECTIVITY = "yes" && -n "$STD_BACKUP_DIR" ]]
     then
      scp "$PRI_BACKUP_DIR/orapw$STD_DB_UNIQUE_NAME" $STD_HOST_IP:$STD_BACKUP_DIR/ 
      scp "$PRI_BACKUP_DIR/init$STD_DB_UNIQUE_NAME.ora" $STD_HOST_IP:$STD_BACKUP_DIR/ 
      scp "$PRI_BACKUP_DIR/auto_tnsnames_by_cdshrewd.${STD_DB_UNIQUE_NAME}.tmp" $STD_HOST_IP:$STD_BACKUP_DIR/
      scp "$PRI_BACKUP_DIR/auto_std_change_param_by_cdshrewd.sh" $STD_HOST_IP:$STD_BACKUP_DIR/
      scp "$PRI_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh" $STD_HOST_IP:$STD_BACKUP_DIR/
      scp "$PRI_BACKUP_DIR/auto_add_standby_logfile_by_cdshrewd.sh" $STD_HOST_IP:$STD_BACKUP_DIR/
  fi
}
transfer_files

change_path_and_privs()
{
USERNAME=$PRI_ORCL_USER
MGRP=`id -ng $PRI_ORCL_USER`
ssh $STD_HOST_IP $STD_BACKUP_DIR/auto_create_dirs_by_cdshrewd.sh
ssh $STD_HOST_IP mv $STD_BACKUP_DIR/orapw$STD_DB_UNIQUE_NAME $REMOTE_ORACLE_HOME/dbs/
ssh $STD_HOST_IP  chown  $USERNAME:$MGRP $REMOTE_ORACLE_HOME/dbs/orapw$STD_DB_UNIQUE_NAME
ssh $STD_HOST_IP mv $STD_BACKUP_DIR/auto_tnsnames_by_cdshrewd.${STD_DB_UNIQUE_NAME}.tmp $REMOTE_ORACLE_HOME/network/admin/tnsnames.ora
ssh $STD_HOST_IP  chown  $USERNAME:$MGRP $REMOTE_ORACLE_HOME/network/admin/tnsnames.ora
ssh $STD_HOST_IP mv $STD_BACKUP_DIR/init$STD_DB_UNIQUE_NAME.ora $REMOTE_ORACLE_HOME/dbs/
ssh $STD_HOST_IP  chown  $USERNAME:$MGRP $REMOTE_ORACLE_HOME/dbs/init$STD_DB_UNIQUE_NAME.ora
ssh $STD_HOST_IP chmod a+x $STD_BACKUP_DIR/*.sh
ssh $STD_HOST_IP chown -R $USERNAME:$MGRP $STD_BACKUP_DIR
}
change_path_and_privs

# check dir is changing or not
check_dir_status()
{
dirname=$1
interval=3
if [ -n $2 ]; then
 len=`echo "$2"|sed 's/[0-9]//g'|sed 's/-//g'`  
 if [ -z $len ]; then
 interval=$2
 fi
fi

if [ -d "$dirname" ]
then
 match_cnt=0
 fsize=`du -sk $dirname|awk '{print $(NF-1)}'`
 ctime=`ls -lrt $dirname|tail -1|awk '{print $(NF-1)}'`
 for ((i=0; i<=3 ; i++))
 do
 cur_ctime=`ls -lrt $dirname|tail -1|awk '{print $(NF-1)}'`
 cur_fsize=`du -sk $dirname|awk '{print $(NF-1)}'`
 if [[ "$ctime" = "$cur_ctime" && "$fsize" -eq "$cur_fsize" ]]; then
 ctime=$cur_ctime
 fszie=$cur_fsize
 let match_cnt+=1;
 sleep $interval
 fi
 done
 if [ $match_cnt -eq 4 ]; then
        return 0
 else
        return 1
 fi
else
echo "$dirname is not a directory."
return 1
fi
}

post_clean()
{
 if [ $CLEAN_STAGE_FILE = "yes" ]; then
 find $PRI_BACKUP_DIR/ -name "auto_*cdshrewd*" -type f -regextype posix-extended -regex ".*\.(sh|ctl|tmp|out)" -exec rm -f {} \;
 ssh $STD_HOST_IP "find $STD_BACKUP_DIR/ -name 'auto_*cdshrewd*' -type f -regextype posix-extended -regex '.*\.(sh|ctl|tmp|out)' -exec rm -f {} \;"
 echo "Staging files in local $PRI_BACKUP_DIR/ and remote "
 echo "$STD_BACKUP_DIR/ directories are removed."
 else
   echo "You did not require cleaning staging files."
   echo "Only remote ssh configuration is restored."
 fi
 ssh $STD_HOST_IP mv /root/.ssh_by_cdshrewd /root/.ssh
}

main()
{
ssh $STD_HOST_IP $STD_BACKUP_DIR/auto_start_std_instance_by_cdshrewd.sh
ssh $STD_HOST_IP $STD_BACKUP_DIR/auto_std_change_param_by_cdshrewd.sh
$PRI_BACKUP_DIR/duplicate_database.sh
sleep 120
while true
do
check_dir_status $TARGET_DATA_DIR $RMAN_FILE_CHECK_INTERVAL
dir_status=$?
RMAN_EXISTS=`ssh $STD_HOST_IP ps -ef|grep rman|grep -v grep|grep cdshrewd|awk '{print $1}'`
if [ x"${RMAN_EXISTS}" = x -a ${dir_status} -eq 0 ]; then
ssh $STD_HOST_IP $STD_BACKUP_DIR/auto_add_standby_logfile_by_cdshrewd.sh
sleep 10
export ORACLE_SID=$STD_DB_UNIQUE_NAME
sqlplus / as sysdba <<SQL
recover managed standby database disconnect from session;
ho sleep 30
recover managed standby database cancel;
alter database open read only;
recover managed standby database using current logfile disconnect from session;
exit
SQL
break;
else
sleep 120
fi
done;
# clean staging files
post_clean
exit
}
main
