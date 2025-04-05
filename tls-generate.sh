#!/usr/bin/env bash

# Generate TLS credentials (private key and public certificate)
# for use in a test environment.
# Generates either a root CA,
# or a certificate signed by the given root CA.

# Format output only if stderr (2) is a terminal (-t).
if [ -t 2 ]
then
  # https://en.wikipedia.org/wiki/ANSI_escape_code
  reset='\033[0m' # No formatting.
  bold='\033[1m'
  red='\033[1;31m'
  green='\033[1;32m'
else
  # Make them all empty (no formatting) if stderr is piped.
  reset=''
  bold=''
  red=''
  green=''
fi

self="$0"

function print-help {
  echo "Usage: $self --ca --key=PATH --cert=PATH"
  echo "       $self NAME --key=PATH --cert=PATH --root-key=PATH --root-cert=PATH"
  echo ''
  echo 'Generate an X-509 certificate and private key pair as PEM-encoded files'
  echo 'written to the paths specified by `--key` and `--cert`.'
  echo ''
  echo 'The first form generates a self-signed root certificate authority.'
  echo 'The second form generates TLS credentials for the site called `NAME`,'
  echo 'using the root CA specified by `--root-key` and `--root-cert`.'
}

key=''
cert=''
ca=0
name=''
root_key=''
root_cert=''

while [[ $# -gt 0 ]]
do
  case "$1" in
    -h|--help)
      print-help
      exit
      ;;
    --ca)
      ca=1
      ;;
    --key=*)
      key="${1#*=}"
      ;;
    --cert=*)
      cert="${1#*=}"
      ;;
    --root-key=*)
      root_key="${1#*=}"
      ;;
    --root-cert=*)
      root_cert="${1#*=}"
      ;;
    --)
      break
      ;;
    *)
      name="$1"
      ;;
  esac
  shift
done

# In case we broke out of the while-loop because the options included `--`.
if [[ $# -gt 0 ]]
then
  # Use the last-supplied argument as the name.
  name="${!#}"
fi

# Must specify `--key` and `--cert` no matter what.
if [[ -z "$key" ]] || [[ -z "$cert" ]]
then
  print-help >&2
  exit 1
fi

# Always generate a private key.
openssl genrsa > "$key" || exit 2

if (( ca ))
then
  if [[ -n "$name" ]] || [[ -n "$root_key" ]] || [[ -n "$root_cert" ]]
  then
    print-help >&2
    exit 1
  fi

  # TODO: Can `/CN` be anything? Is `-subj` even necessary?
  openssl req -new -key "$key" -subj "/CN=ROOT" \
    -addext 'keyUsage=critical,keyCertSign' \
    -addext 'basicConstraints=critical,CA:TRUE' \
    | openssl x509 -req -key "$key" \
      -copy_extensions copy \
      > "$cert"
else
  if [[ -z "$name" ]] || [[ -z "$root_key" ]] || [[ -z "$root_cert" ]]
  then
    print-help >&2
    exit 1
  fi

  openssl req -new -key "$key" -subj "/CN=$name" \
    -addext 'keyUsage=critical,digitalSignature' \
    -addext "subjectAltName = DNS:$name" \
    | openssl x509 -req -CA "$root_cert" -CAkey "$root_key" \
      -copy_extensions copy \
      > "$cert"
fi
