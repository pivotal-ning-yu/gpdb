#!/bin/sh
#Code given by Jasper

echodo()
{
    echo "${@}"
    (${@})
}

yearmon()
{
    date '+%Y%m%d'
}

create_certificate()
{
#Input for Subject prompt
C=AU
ST=SA
L=Adelaide
O=codenes
OU=nes
DATE=`yearmon`
CN=${1:-$(cat /etc/hosts | grep `hostname` | awk '{print $1;}')}

if [ -z "$CN" ]; then
	CN=${1:-$(cat /etc/hosts | grep test1 | awk '{print $1;}')}
fi

csr="server.req"
key="server.key"
cert="server.crt"

# Create the certificate signing request
openssl req -new -passin pass:password -passout pass:password -text -out $csr <<EOF
${C}
${ST}
${L}
${O}
${OU}
${CN}
$USER@${CN}
.
.
EOF
echo ""

[ -f ${csr} ] && echodo openssl req -text -noout -in ${csr}
echo ""

# Create the Key
openssl rsa -in privkey.pem -passin pass:password -passout pass:password -out ${key}

# Create the Certificate
openssl x509 -in ${csr} -out ${cert} -req -signkey ${key} -days 1000

chmod og-rwx ${key}
}

## MAIN
create_certificate

mkdir -p certificate/server/.

cp server.key certificate/server/.
cp server.crt certificate/server/.
cp server.crt certificate/server/root.crt

mkdir -p certificate/gpfdists

cp server.key certificate/gpfdists/client.key
cp server.crt certificate/gpfdists/client.crt
cp server.crt certificate/gpfdists/root.crt

rm -f server.*

# Create extra certificate for wrong cert

mkdir -p certificate/server_wrong

create_certificate

cp server.key certificate/server_wrong/.
cp server.crt certificate/server_wrong/.
cp server.crt certificate/server_wrong/root.crt

rm -f server.*
