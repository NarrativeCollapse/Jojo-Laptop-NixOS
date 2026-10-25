# cac-setup [bundle.zip]: import the DoD's CA certificates into LibreWolf,
# so DoD sites are trusted. (The card itself is read through OpenSC, which
# LibreWolf loads on its own; see modules/smartcard.nix, which builds this
# and sets PATH.) Safe to run again, e.g. when DISA publishes a new bundle.

url=https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_DoD.zip
page=https://public.cyber.mil/pki-pke/tools-configuration-files/

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# 1. LibreWolf's profiles: each has its own certificate store.
mapfile -t profiles < <(find "$HOME/.librewolf" "${XDG_CONFIG_HOME:-$HOME/.config}/librewolf" \
  -maxdepth 3 -name cert9.db -printf '%h\n' 2>/dev/null | sort -u)
if [ "${#profiles[@]}" -eq 0 ]; then
  echo "No LibreWolf profile found. Open LibreWolf once, close it, then run cac-setup again."
  exit 1
fi

# 2. The bundle: the zip given, or the current one from DISA.
if [ $# -ge 1 ]; then
  zip=$1
  if [ ! -f "$zip" ]; then
    echo "No such file: $zip"
    exit 1
  fi
else
  echo "Downloading the DoD certificate bundle from DISA..."
  zip=$work/dod.zip
  if ! curl -fsSL --max-time 120 -o "$zip" "$url"; then
    echo
    echo "Couldn't download it (offline, or DISA renamed the file for a new version)."
    echo "Download it in a browser instead: on $page"
    echo "get \"PKI CA Certificate Bundles: PKCS#7 for DoD PKI Only\", then run:"
    echo "  cac-setup ~/Downloads/<the zip file>"
    exit 1
  fi
fi

# 3. Every certificate in it, once. The zip holds the same certificates in
# several PKCS#7 files (PEM and DER); collect them all, then split them up.
mkdir "$work/zip" "$work/certs"
if ! unzip -q -o "$zip" -d "$work/zip" 2>/dev/null; then
  echo "$zip isn't a zip file. Use the DoD PKCS#7 bundle from $page"
  exit 1
fi
while IFS= read -r -d "" p7b; do
  openssl pkcs7 -print_certs -in "$p7b" 2>/dev/null \
    || openssl pkcs7 -print_certs -inform DER -in "$p7b" 2>/dev/null \
    || true
done < <(find "$work/zip" -iname '*.p7b' -print0) >"$work/all.pem"
awk -v dir="$work/certs" '
  /-----BEGIN CERTIFICATE-----/ { n++; file = sprintf("%s/%04d.pem", dir, n) }
  file { print > file }
  /-----END CERTIFICATE-----/ { close(file); file = "" }
' "$work/all.pem"

roots=0 others=0 failed=0
declare -A seen
for cert in "$work"/certs/*.pem; do
  [ -e "$cert" ] || continue
  fingerprint=$(openssl x509 -noout -fingerprint -sha256 -in "$cert")
  [ -z "${seen[$fingerprint]:-}" ] || continue
  seen[$fingerprint]=1
  name=$(openssl x509 -noout -subject -nameopt multiline -in "$cert" | awk -F ' = ' '/^ *commonName/ && !done { print $2; done = 1 }')
  [ -n "$name" ] || name=$fingerprint
  # Root CAs (self-signed) are trusted for websites; the CAs under them
  # are added untrusted, so LibreWolf can build the chain to a root.
  if [ "$(openssl x509 -noout -subject -in "$cert" | sed 's/^subject=//')" = \
    "$(openssl x509 -noout -issuer -in "$cert" | sed 's/^issuer=//')" ]; then
    trust="CT,C,C" kind=root
  else
    trust=",," kind=other
  fi
  ok=1
  for profile in "${profiles[@]}"; do
    certutil -A -d "sql:$profile" -n "$name" -t "$trust" -i "$cert" 2>/dev/null || ok=0
  done
  if [ "$ok" -eq 0 ]; then
    failed=$((failed + 1))
  elif [ "$kind" = root ]; then
    roots=$((roots + 1))
  else
    others=$((others + 1))
  fi
done

if [ $((roots + others)) -eq 0 ]; then
  echo "No certificates found in $zip. Use the DoD PKCS#7 bundle from $page"
  exit 1
fi
echo "Imported into ${#profiles[@]} LibreWolf profile(s): $roots DoD root CAs and $others other DoD CAs."
if [ "$failed" -gt 0 ]; then
  echo "($failed couldn't be imported; usually harmless, an older copy of the same CA.)"
fi
echo
echo "Restart LibreWolf. Then, with the reader plugged in and the card in it:"
echo "  pcsc_scan                 shows the reader and the card (Ctrl+C to stop)"
echo "  pkcs11-tool --list-slots  shows the card's certificates slot"
echo "and open a CAC site in LibreWolf: it asks for the card's PIN."
