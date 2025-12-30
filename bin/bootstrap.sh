#!/bin/sh
set -e

VELLUM_ROOT="/home/root/.vellum"
VELLUM_REPO="https://raw.githubusercontent.com/rmitchellscott/vellum/main"
APK_VERSION="3.0.3-r1"

echo "Installing vellum..."

ARCH=$(uname -m)
case "$ARCH" in
    aarch64) APK_ARCH="aarch64" ;;
    armv7l)  APK_ARCH="armv7" ;;
    *)       echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

mkdir -p "$VELLUM_ROOT"/{bin,etc/apk/keys,state,local-repo,cache,lib/apk/db}

echo "Downloading apk.static..."
APK_URL="https://dl-cdn.alpinelinux.org/alpine/edge/main/$APK_ARCH/apk-tools-static-$APK_VERSION.apk"
cd /tmp
wget -q "$APK_URL" -O apk-tools-static.apk
tar -xzf apk-tools-static.apk sbin/apk.static
mv sbin/apk.static "$VELLUM_ROOT/bin/"
chmod +x "$VELLUM_ROOT/bin/apk.static"
rm -rf apk-tools-static.apk sbin

echo "Downloading vellum..."
mv /tmp/vellum "$VELLUM_ROOT/bin/vellum"
# wget -q "$VELLUM_REPO/bin/vellum" -O "$VELLUM_ROOT/bin/vellum"
chmod +x "$VELLUM_ROOT/bin/vellum"

echo "Downloading signing key..."
mv /tmp/packages.rsa.pub "$VELLUM_ROOT/etc/apk/keys/packages.rsa.pub"
# wget -q "$VELLUM_REPO/keys/packages.rsa.pub" -O "$VELLUM_ROOT/etc/apk/keys/packages.rsa.pub"

echo "Generating local signing key..."
if [ ! -f "$VELLUM_ROOT/etc/apk/keys/local.rsa" ]; then
    openssl genrsa -out "$VELLUM_ROOT/etc/apk/keys/local.rsa" 2048 2>/dev/null
    openssl rsa -in "$VELLUM_ROOT/etc/apk/keys/local.rsa" -pubout -out "$VELLUM_ROOT/etc/apk/keys/local.rsa.pub" 2>/dev/null
fi

echo "Configuring repositories..."
cat > "$VELLUM_ROOT/etc/apk/repositories" <<EOF
/home/root/.vellum/local-repo
https://packages.vellum.delivery
EOF

echo "Setting up /usr/lib overlay for apk database..."
mkdir -p "$VELLUM_ROOT/lib-overlay/upper" "$VELLUM_ROOT/lib-overlay/work"
if ! mountpoint -q /usr/lib 2>/dev/null; then
    mount -t overlay overlay \
        -o "lowerdir=/usr/lib,upperdir=$VELLUM_ROOT/lib-overlay/upper,workdir=$VELLUM_ROOT/lib-overlay/work" \
        /usr/lib
fi
mkdir -p /lib/apk/db

echo "Initializing apk database..."
"$VELLUM_ROOT/bin/apk.static" \
    --keys-dir "$VELLUM_ROOT/etc/apk/keys" \
    --repositories-file "$VELLUM_ROOT/etc/apk/repositories" \
    --no-logfile \
    add --initdb

echo "Updating package index..."
"$VELLUM_ROOT/bin/vellum" update

BASHRC="/home/root/.bashrc"
PATH_LINE="export PATH=\"$VELLUM_ROOT/bin:\$PATH\""

if [ -f "$BASHRC" ] && grep -qF ".vellum/bin" "$BASHRC"; then
    echo "PATH already configured in $BASHRC"
else
    echo "" >> "$BASHRC"
    echo "$PATH_LINE" >> "$BASHRC"
    echo "Added vellum to PATH in $BASHRC"
fi

echo ""
echo "Vellum installed successfully!"
echo "Run 'source ~/.bashrc' or start a new shell to use vellum."
