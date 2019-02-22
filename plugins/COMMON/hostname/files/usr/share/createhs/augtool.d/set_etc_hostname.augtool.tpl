# augtool -s --noload --include=/usr/share/createhs/augeas.d
load-file /etc/hostname
rm  /files/etc/hostname
set /files/etc/hostname/hostname ${ETC_HOSTNAME}
