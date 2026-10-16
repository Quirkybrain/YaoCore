#!/usr/bin/env python3
"""Derive a YaoCore per-module key without putting the master secret in argv."""

import argparse
import getpass
import hashlib
import hmac
import re


ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,62}$")


def derive(master_secret: str, module_id: str) -> str:
    if not ID_PATTERN.fullmatch(module_id):
        raise ValueError("moduleId must match ^[A-Za-z0-9][A-Za-z0-9_.:-]{0,62}$")
    if len(master_secret.encode("utf-8")) < 16:
        raise ValueError("gateway master secret must contain at least 16 UTF-8 bytes")
    context = f"YAOCORE-MODULE-KEY-V1\n{module_id}".encode("utf-8")
    return hmac.new(master_secret.encode("utf-8"), context, hashlib.sha256).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description="Derive a YaoCore module key")
    parser.add_argument("module_id", help="stable moduleId configured in the external module")
    args = parser.parse_args()
    secret = getpass.getpass("Gateway master command secret: ")
    print(derive(secret, args.module_id))


if __name__ == "__main__":
    main()
