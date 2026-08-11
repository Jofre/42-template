#!/bin/sh
# ex03 — id_ed25519_pub must be a valid ed25519 PUBLIC key (256 bits).
# (We can't pin a specific key — every student's key material differs; check
#  properties. The random base64 blob is the "answer" and is never shown.)
#
# The subject stresses: "Make sure you understand the difference between the
# public key and the private key." That warning matters here because
# `ssh-keygen -l -f <file>` (below) ALSO succeeds on a *private* key file — it
# just derives and prints the public fingerprint — and reports "256 (ED25519)"
# all the same. So the fingerprint checks alone do NOT catch the classic KO of
# turning in the private key. We add public-key-format assertions that a PEM
# private key ("-----BEGIN OPENSSH PRIVATE KEY-----", multi-line) fails.
# shellcheck source=../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

KEY=${1:-id_ed25519_pub}
printf "  CHECK: %s\n" "$KEY"

ck "file id_ed25519_pub exists" test -f "$KEY"

info=$(ssh-keygen -l -f "$KEY" 2>/dev/null)
ck "ssh-keygen recognises it as a public key" test -n "$info"

# key type, as reported by ssh-keygen -l, must be ED25519
type=$(printf '%s' "$info" | sed -n 's/.*(\([^)]*\)).*/\1/p')
ck_eq "key type" "$type" "ED25519"

# ed25519 keys are always 256 bits; the fingerprint listing begins with the bit length
bits=$(printf '%s' "$info" | awk '{print $1}')
ck_eq "key size (bits)" "$bits" "256"

# --- PUBLIC-vs-PRIVATE guard (the KO the checks above are blind to) ----------
# An OpenSSH public key is a single line whose first field is the algorithm name
# ("ssh-ed25519 <base64> [comment]"). A private key file is multi-line PEM
# starting with "-----BEGIN". "ssh-ed25519" is the algorithm identifier (a format
# constant, like the "ED25519"/"256" shown above) — not the secret key material.
first=$(head -n1 "$KEY" 2>/dev/null | awk '{print $1}')
ck "delivered file is a PUBLIC key (ssh-ed25519 ...), not the private key" \
	test "$first" = "ssh-ed25519"

# No private-key material may leak into the deliverable.
ck "contains no private-key material" \
	sh -c 'case "$(cat "$1" 2>/dev/null)" in *"PRIVATE KEY"*) exit 1;; *) exit 0;; esac' _ "$KEY"

# A public key is exactly one line; a PEM private key spans several.
keylines=$(grep -c . "$KEY" 2>/dev/null)
ck_eq "public key is a single line" "$keylines" "1"

ck_report
