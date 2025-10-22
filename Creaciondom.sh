sudo samba-tool domain provision --realm=RICARDO.MARTI.FP --domain=RICARDO \
  --adminpass="Administr@d0r" --server-role=dc --dns-backend=BIND9_DLZ \
  --use-rfc2307 --use-xattrs=auto \
  --option="interfaces=lo enp0s8" --option="bind interfaces only=yes"
