#!/usr/bin/env python3
# Generates and applies a randomized, deterministic, or static IMEI on the
# GL.iNet Mudi 7 (GL-E5800), which uses the Qualcomm Snapdragon X72
# (Dragonwing MBB Gen 3) 5G modem with dual nano-SIM support.
#
# The X72 is attached over MHI/PCIe and does not expose the legacy
# /dev/ttyUSB3 control port that the Quectel EP06 used. We therefore
# talk to the modem through GL.iNet's `gl_modem` helper, which abstracts
# the AT transport and is part of gl-sdk4 firmware.

import argparse
import random
import re
import string
import subprocess
from enum import Enum
from functools import reduce


class Modes(Enum):
    DETERMINISTIC = 1
    RANDOM = 2
    STATIC = 3


GL_MODEM = "/usr/bin/gl_modem"

# AT command template used to write a new IMEI. The X72 modem firmware
# shipped on the Mudi 7 accepts the Quectel-style EGMR write (confirmed
# via the GL.iNet web UI). Override with --at-write if a future
# firmware uses a different command.
DEFAULT_AT_WRITE = 'AT+EGMR=1,7,"{imei}"'

imei_length = 14  # without validation digit
imei_prefix = ["35674108", "35290611", "35397710", "35323210", "35384110",
               "35982748", "35672011", "35759049", "35266891", "35407115",
               "35538025", "35480910", "35324590", "35901183", "35139729",
               "35479164"]

verbose = False
mode = None


def gl_modem_at(cmd, slot=None, timeout=10):
    args = [GL_MODEM]
    if slot is not None:
        args += ["-s", str(slot)]
    args += ["AT", cmd]
    if verbose:
        print(f"Running: {' '.join(args)}")
    try:
        proc = subprocess.run(args, capture_output=True, timeout=timeout)
    except FileNotFoundError:
        raise RuntimeError(f"{GL_MODEM} not found; this script requires gl-sdk4")
    output = (proc.stdout or b"") + (proc.stderr or b"")
    if verbose:
        print(f"AT {cmd!r} -> {output!r}")
    return output


def get_imsi(slot=None):
    output = gl_modem_at("AT+CIMI", slot=slot)
    imsi_d = re.findall(rb"[0-9]{15}", output)
    return b"".join(imsi_d)


def get_imei(slot=None):
    output = gl_modem_at("AT+GSN", slot=slot)
    imei_d = re.findall(rb"[0-9]{14,15}", output)
    return b"".join(imei_d)


def set_imei(imei, slot=None, at_write=DEFAULT_AT_WRITE):
    cmd = at_write.format(imei=imei)
    gl_modem_at(cmd, slot=slot)
    new_imei = get_imei(slot=slot)
    if new_imei.startswith(imei.encode()):
        print("IMEI has been successfully changed.")
        return True
    print(f"IMEI has not been successfully changed. Modem reports {new_imei!r}.")
    return False


def generate_imei(prefixes, imsi_d):
    if mode == Modes.DETERMINISTIC:
        random.seed(imsi_d)
    imei = random.choice(prefixes)
    if verbose:
        print(f"IMEI prefix: {imei}")
    random_part_length = imei_length - len(imei)
    imei += "".join(random.sample(string.digits, random_part_length))
    if verbose:
        print(f"IMEI without validation digit: {imei}")

    iteration_1 = "".join(
        [c if i % 2 == 0 else str(2 * int(c)) for i, c in enumerate(imei)]
    )
    s = reduce(lambda a, b: int(a) + int(b), iteration_1)
    validation_digit = (10 - int(str(s)[-1])) % 10
    if verbose:
        print(f"Validation digit: {validation_digit}")
    return f"{imei}{validation_digit}"


def validate_imei(imei):
    if len(imei) != 14:
        print(f"NOT A VALID IMEI: {imei} - IMEI must be 14 characters in length")
        return False
    validation_digit = int(imei[-1])
    iteration_1 = "".join(
        [c if i % 2 == 0 else str(2 * int(c)) for i, c in enumerate(imei[0:14])]
    )
    s = reduce(lambda a, b: int(a) + int(b), iteration_1)
    expect = (10 - int(str(s)[-1])) % 10
    if validation_digit == expect:
        print(f"{imei} is CORRECT")
        return True
    print(f"NOT A VALID IMEI: {imei}")
    return False


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="Enables verbose output")
    ap.add_argument("-g", "--generate-only", action="store_true",
                    help="Only generates an IMEI rather than setting it")
    ap.add_argument("--slot", type=int, choices=[1, 2], default=None,
                    help="SIM slot to operate on (Mudi 7 is dual-SIM). "
                         "Defaults to the active slot.")
    ap.add_argument("--at-write", default=DEFAULT_AT_WRITE,
                    help="AT command template used to write the IMEI; "
                         "{imei} is substituted.")
    modes = ap.add_mutually_exclusive_group()
    modes.add_argument("-d", "--deterministic", action="store_true",
                       help="Switches IMEI generation to deterministic mode")
    modes.add_argument("-s", "--static", action="store",
                       help="Sets user-defined IMEI")
    modes.add_argument("-r", "--random", action="store_true",
                       help="Sets random IMEI")
    args = ap.parse_args()

    verbose = args.verbose
    imsi_d = None
    if args.deterministic:
        mode = Modes.DETERMINISTIC
        imsi_d = get_imsi(slot=args.slot)
    elif args.random:
        mode = Modes.RANDOM
    elif args.static is not None:
        mode = Modes.STATIC

    if mode == Modes.STATIC:
        if validate_imei(args.static):
            if not set_imei(args.static, slot=args.slot, at_write=args.at_write):
                exit(-1)
        else:
            exit(-1)
    else:
        imei = generate_imei(imei_prefix, imsi_d)
        if verbose:
            print(f"Generated new IMEI: {imei}")
        if not args.generate_only:
            if not set_imei(imei, slot=args.slot, at_write=args.at_write):
                exit(-1)

    exit(0)
