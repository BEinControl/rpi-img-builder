load-file /etc/hosts
defvar  hosts /files/etc/hosts
rm      $hosts/*[ipaddr="127.0.1.1"]
ins     01 after $hosts/*[ipaddr="127.0.0.1"]
set     $hosts/01/ipaddr "127.0.1.1"
set     $hosts/01/canonical ${ETC_HOSTNAME}
