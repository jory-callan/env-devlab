#!/bin/bash

# Generate a self-signed CA + server certificate pair for local development.
# The output files are written to the current working directory.

# Input parameters
read -p "Enter domain (default www.example.com): " DOMAIN
DOMAIN=${DOMAIN:-www.example.com}

read -p "Enter private key password (default 123456): " PASSWD
PASSWD=${PASSWD:-123456}
echo $PASSWD > $DOMAIN.passwd.txt

read -p "Enter certificate validity in days (default 36500): " DAYS
DAYS=${DAYS:-36500}

# Generate the CA key and certificate
echo "Generating CA private key"
openssl genrsa -passout file:$DOMAIN.passwd.txt -aes128 -out $DOMAIN.ca.key 2048

echo "Generating password-free CA private key"
openssl rsa -passin file:$DOMAIN.passwd.txt -in $DOMAIN.ca.key -out $DOMAIN.ca.no.key

echo "Generating CA root certificate"
SUBJECT="/C=US/SN=NYC/L=HardCorp-1/O=Organization/OU=HardCorp-1/CN=$DOMAIN"
openssl req -new -x509 -days $DAYS -sha1 -extensions v3_ca -subj "$SUBJECT" -key $DOMAIN.ca.no.key -out $DOMAIN.ca.crt

# Generate the server key
echo "Generating server private key"
openssl genrsa -passout file:$DOMAIN.passwd.txt -aes128 -out $DOMAIN.server.key 2048

# Generate the password-free server key
echo "Generating password-free server private key"
openssl rsa -passin file:$DOMAIN.passwd.txt -in $DOMAIN.server.key -out $DOMAIN.server.no.key

# Generate the server CSR and sign it with the CA
echo "Generating server certificate request (CSR)"
openssl req -new -days $DAYS -sha1 -extensions v3_ca -subj "$SUBJECT" -key $DOMAIN.server.no.key -out $DOMAIN.server.csr
echo "Signing the server certificate with the CA"
# This also creates the $DOMAIN.srl serial file, which records how many
# certificates the CA has issued; each signed certificate gets an
# incremented, unique serial number.
openssl x509 -days $DAYS -req -in $DOMAIN.server.csr -CA $DOMAIN.ca.crt -CAkey $DOMAIN.ca.no.key -CAcreateserial -out $DOMAIN.server.crt

# Output locations
echo "Certificate: /$DOMAIN.server.crt"
echo "Private key: /$DOMAIN.server.no.key"

echo """
SSL/TLS certificate file formats:
    CA root cert (ca.crt):     self-signed certificate representing the
                               certificate authority, used to sign
                               lower-level certificates.
    Server cert (server.crt):  deployed on the server, signed by the CA,
                               used to prove the server identity to clients.
    Client cert (client.crt):  deployed on the client, signed by the CA,
                               used to prove the client identity to servers.
    .key files:                the private key matching a certificate;
                               required on the server side.
    .csr files:                certificate signing request, generated when
                               requesting a certificate and submitted to a CA.
    .pem files:                PEM-encoded certificate file, human-readable
                               text format.
    .crt files:                certificate file, usually in PEM format; CRT
                               is the common extension for certificates.
"""

echo "TODO:"
echo "Copy $DOMAIN.server.crt to ../ssl/$DOMAIN.crt"
echo "Copy $DOMAIN.server.no.key to ../ssl/$DOMAIN.key"
echo "Add configuration in nginx:"
echo "server {"
echo "    ..."
echo "    listen 443 ssl;"
echo "    ssl_certificate     /etc/nginx/ssl/$DOMAIN.crt;"
echo "    ssl_certificate_key /etc/nginx/ssl/$DOMAIN.key;"
echo "}"
