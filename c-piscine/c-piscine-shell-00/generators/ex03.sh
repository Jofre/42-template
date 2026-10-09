#!/bin/sh
# ex03 — id_ed25519_pub: the public half of an ed25519 key pair, and never the
# private half, which does not enter the repository.
#
# This file runs again on every generate and every submit. The tests run it
# under a HOME that is not yours, from an empty directory holding no other file
# of the repository, so it can rely on nothing but this file and the directory
# it runs in.
# TODO: write the commands that create this deliverable in the current dir.
:
