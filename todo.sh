#!/bin/bash
# ==========================================================
# Instalación automática de SAMBA 4.20.5 como AD DC en Rocky Linux 9.4
# Autor: Nano & Ricardo
# Dominio: ricardo.marti.fp
# Hostname: ricardo
# IP Interna: 172.18.0.1/16
# Contraseña Administrator: Administr@d0r
# ==========================================================

set -e  # Detener script si ocurre un error

echo "===== [1/14] Instalando herramientas básicas ====="
sudo dnf -y install bash-completion vim nano wget curl unzip net-tools epel-release

source /etc/profile.d/bash_completion.sh

echo "===== [2/14] Verificando SELinux ====="
sestatus || true

echo "===== [3/14] Configurando red interna ====="
sudo nmcli connection modify "Conexión cableada 1" con-name enp0s8 || true
sudo nmcli connection modify enp0s8 ipv4.addresses 172.18.0.1/16 connection.autoconnect yes ipv4.never-default yes ipv4.method manual
sudo nmcli connection modify enp0s8 ipv6.method disabled
sudo nmcli con down enp0s8 || true
sudo nmcli con up enp0s8

echo "===== [4/14] Configurando hostname ====="
sudo hostnamectl set-hostname ricardo.marti.fp
echo "ricardo.marti.fp" | sudo tee /etc/hostname

echo "===== [5/14] Configurando /etc/hosts ====="
cat <<EOF | sudo tee /etc/hosts
127.0.0.1   localhost localhost.localdomain
::1         localhost localhost.localdomain
172.18.0.1  ricardo ricardo.marti.fp
EOF

echo "===== [6/14] Instalando herramientas de desarrollo ====="
sudo dnf -y groupinstall "Development Tools"
sudo dnf -y config-manager --set-enable crb
sudo dnf -y install docbook-style-xsl gcc gdb gnutls-devel gpgme-devel \
  jansson-devel keyutils-libs-devel krb5-workstation libacl-devel libaio-devel \
  libarchive-devel libattr-devel libblkid-devel libtasn1 libtasn1-tools libxml2-devel \
  libxslt lmdb-devel openldap-devel pam-devel perl perl-ExtUtils-MakeMaker \
  perl-Parse-Yapp popt-devel python3-cryptography python3-dns python3-gpg \
  python3-devel readline-devel rpcgen systemd-devel tar zlib-devel perl-JSON \
  libtirpc-devel dbus-devel python3-pyasn1 python3-markdown bind bind-libs bind-utils

echo "===== [7/14] Descargando y compilando Samba 4.20.5 ====="
cd ~
wget -q https://ftp.samba.org/pub/samba/samba-pubkey.asc
wget -q https://ftp.samba.org/pub/samba/samba-4.20.8.tar.gz
tar -xzf samba-4.20.8.tar.gz
cd samba-4.20.8

./configure \
  --prefix=/usr \
  --sysconfdir=/etc \
  --localstatedir=/var \
  --with-piddir=/run/samba \
  --with-pammodulesdir=/lib/security \
  --enable-fhs \
  --with-systemd \
  --systemd-install-services \
  --enable-selftest

make -j"$(nproc)"
sudo make install

echo "===== [8/14] Deshabilitando firewall temporalmente ====="
sudo systemctl disable --now firewalld || true

echo "===== [9/14] Creando dominio AD con samba-tool ====="
sudo samba-tool domain provision --realm=RICARDO.MARTI.FP --domain=RICARDO \
  --adminpass="Administr@d0r" --server-role=dc --dns-backend=BIND9_DLZ \
  --use-rfc2307 --use-xattrs=auto \
  --option="interfaces=lo enp0s8" --option="bind interfaces only=yes"

echo "===== [10/14] Configurando SELinux ====="
sudo setsebool -P samba_create_home_dirs=on samba_domain_controller=on \
  samba_enable_home_dirs=on samba_portmapper=on use_samba_home_dirs=on
sudo restorecon -Rv /

echo "===== [11/14] Configurando BIND (DNS) ====="
sudo cp /etc/named.conf{,.$(date +%F)}
sudo sed -i '/listen-on-v6/s/^/#/' /etc/named.conf
sudo sed -i '/include "\/etc\/crypto-policies\/back-ends\/bind.config";/a include "/var/lib/samba/bind-dns/named.conf";' /etc/named.conf
sudo systemctl enable --now named

echo "===== [12/14] Configurando Kerberos ====="
sudo mv /etc/krb5.conf{,.$(date +%F)}
sudo cp -Z /var/lib/samba/private/krb5.conf /etc/

echo "===== [13/14] Habilitando servicio Samba ====="
sudo systemctl mask smb nmb winbind
sudo systemctl enable --now samba

echo "===== [14/14] Configuración finalizada ====="
echo "-----------------------------------------------------"
echo "Dominio AD creado: ricardo.marti.fp"
echo "Hostname: ricardo.marti.fp"
echo "Administrador: Administrator / Contraseña: Administr@d0r"
echo "-----------------------------------------------------"
echo "Puedes verificar con:"
echo "  smbclient -L localhost -U%"
echo "  samba-tool domain level show"
echo "  kinit administrator@RICARDO.MARTI.FP"

#!/bin/bash
# ==========================================================
# SAMBA 4.20.8 - Configuración de servicios y comprobaciones finales
# Autor: Nano & Ricardo
# Desde el punto 6.6 (Verificación de configuración) hasta 7.5.4
# Dominio: ricardo.marti.fp
# Hostname: ricardo
# IP Interna: 172.18.0.1/16
# ==========================================================

set -e

echo "===== [6.6] Verificando instalación de Samba y Kerberos ====="

echo "--- Versión de Samba ---"
samba -V
smbclient -V

echo "--- Listado de recursos compartidos ---"
smbclient -L localhost -U% || true

echo "--- Registros DNS principales ---"
host -t SRV _ldap._tcp.ricardo.marti.fp. || true
host -t SRV _kerberos._udp.ricardo.marti.fp. || true
host -t A ricardo.marti.fp. || true

echo "--- Verificando Kerberos ---"
kinit administrator@RICARDO.MARTI.FP || true
klist || true

echo "===== [6.7] Probando actualizaciones dinámicas de DNS ====="
sudo samba_dnsupdate --verbose --all-names || true

echo "===== [6.8] Configurando DHCP ====="
sudo dnf -y install dhcp-server

cat <<EOF | sudo tee /etc/dhcp/dhcpd.conf
# Configuración DHCP Samba 4 (red interna)
authoritative;
option domain-name "ricardo.marti.fp";
option domain-name-servers 172.18.0.1;
option ntp-servers 172.18.0.1;
option domain-search "ricardo.marti.fp";
default-lease-time 600;
max-lease-time 7200;
adaptive-lease-time-threshold 70;
log-facility local7;
one-lease-per-client on;
option time-offset 3600;

subnet 172.18.0.0 netmask 255.255.0.0 {
        range 172.18.0.10 172.18.0.199;
        option routers 172.18.0.1;
}
EOF

sudo dhcpd -t
sudo systemctl enable --now dhcpd

echo "===== [7.1-7.2] Configurando zonas de red ====="
sudo nmcli connection modify enp0s3 connection.zone external
sudo nmcli connection modify enp0s8 connection.zone internal
sudo systemctl restart NetworkManager
nmcli -g connection.id,connection.zone connection show enp0s{3,8}

echo "===== [7.3] Levantando el cortafuegos ====="
sudo systemctl enable --now firewalld
sudo firewall-cmd --get-active-zones

echo "===== [7.4] Comprobando enrutamiento ====="
sudo firewall-cmd --zone=external --query-masquerade || sudo firewall-cmd --zone=external --add-masquerade --permanent
sysctl net.ipv4.ip_forward

echo "===== [7.5] Configurando cortafuegos ====="
sudo firewall-cmd --zone=internal --list-all

# Eliminamos servicios innecesarios
sudo firewall-cmd --permanent --zone=internal --remove-service={samba-client,mdns,dhcpv6-client} || true
sudo firewall-cmd --reload
sudo firewall-cmd --zone=internal --list-services

echo "===== [7.5.1 - 7.5.3] Abriendo puertos necesarios ====="
sudo firewall-cmd --permanent --zone=internal --add-service=dhcp
sudo firewall-cmd --permanent --zone=internal --add-service=samba-dc
sudo firewall-cmd --permanent --zone=internal --add-service=ntp
sudo firewall-cmd --reload

echo "===== [7.5.4] Comprobando enrutamiento entre interfaces ====="
echo "Reglas activas:"
sudo firewall-cmd --list-all-zones | grep -E 'interfaces|services|masquerade' || true

echo "===== ✅ SERVIDOR COMPLETAMENTE CONFIGURADO ====="
echo "-----------------------------------------------------"
echo "Dominio: ricardo.marti.fp"
echo "Hostname: ricardo.marti.fp"
echo "Administrador: Administrator / Administr@d0r"
echo "-----------------------------------------------------"
echo "Servicios activos:"
sudo systemctl status samba named chronyd dhcpd firewalld --no-pager
echo "-----------------------------------------------------"
echo "Puedes probar los clientes Windows y Linux ahora."
echo "En Windows: unir al dominio 'ricardo.marti.fp'"
echo "En Linux: usar 'realm join ricardo.marti.fp -U Administrator'"

