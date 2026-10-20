#!/bin/bash

# Check the remaining validity of an SSL certificate, either by querying a
# live HTTPS endpoint or by reading a certificate file from disk.

# Usage message
if [ $# -ne 1 ]; then
    echo "Usage: $0 <domain | certificate-file-path>"
    echo "Example: $0 h5.example.com"
    echo "Example: $0 /data/ssl/h5.example.com.cer"
    exit 1
fi

TARGET="$1"

# Domain target: fetch the certificate from the live endpoint
if [[ "$TARGET" =~ ^https?:// ]] || [[ "$TARGET" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    DOMAIN="$TARGET"
    if [[ ! "$DOMAIN" =~ ^https?:// ]]; then
        DOMAIN="https://$DOMAIN"
    fi

    EXPIRE_DATE=$(echo | openssl s_client -servername "${TARGET}" -connect "${TARGET}:443" 2>/dev/null \
        | openssl x509 -noout -enddate \
        | cut -d= -f2)

# Certificate file target: read the expiry from the local file
elif [ -f "$TARGET" ]; then
    EXPIRE_DATE=$(openssl x509 -in "$TARGET" -noout -enddate | cut -d= -f2)
else
    echo "ERROR: unrecognized target: $TARGET"
    exit 1
fi

# Compute the remaining validity in days
EXPIRE_TIMESTAMP=$(date -d "$EXPIRE_DATE" +%s)
NOW_TIMESTAMP=$(date +%s)

DAYS_LEFT=$(( (EXPIRE_TIMESTAMP - NOW_TIMESTAMP) / 86400 ))

echo "SSL certificate expiry date: $EXPIRE_DATE"
echo "Days remaining: $DAYS_LEFT"

if [ "$DAYS_LEFT" -lt 30 ]; then
    echo "WARNING: the certificate is about to expire!"
elif [ "$DAYS_LEFT" -lt 0 ]; then
    echo "ERROR: the certificate has expired!"
else
    echo "OK: the certificate is valid"
fi
