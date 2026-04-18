#!/usr/bin/python3
##
# config_gen.py
##
# Purpose: create config.toml for fan-control.py to use
##
# Notes: This generator supports multiple preset profiles so the repo does not need one near-duplicate script per OS.

import argparse
import copy
import json
import os

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib

CONFIG_PATH = "config.toml"
DEFAULT_PROFILE = "Proxmox"

COMMON_CONFIG = {
    "fan_curve": {
        "cpu": [
            [0, 0],
            [25, 20],
            [35, 20],
            [40, 25],
            [45, 30],
            [50, 40],
            [60, 50],
            [70, 60],
            [80, 100],
            [90, 100],
            [100, 100],
        ],
        "hdd": [
            [0, 0],
            [25, 25],
            [35, 25],
            [40, 30],
            [45, 35],
            [50, 40],
            [60, 50],
            [70, 70],
            [80, 80],
            [90, 100],
            [100, 100],
        ],
    },
    "hdd_panic": {
        "max_temp": 50,
        "panic_addition": 5,
    },
    "detect_timers": {
        "cpu_timer": 1,
        "hdd_timer": 30,
    },
    "log_config": {
        "file_name": "/root/fan-control/fan-control.log",
        "format": "%(asctime)s %(levelname)s: %(message)s",
        "date_format": "%Y/%m/%d %I:%M:%S %p",
        "frequency": "On_Change",
    },
}

PROFILE_OVERRIDES = {
    "Proxmox": {
        "system_info": {
            "system_os": "Proxmox",
            "ipmi_type": "iDRAC_Gen08",
            "single_zone": True,
            "temp_focus": "Both",
            "disks": ["sda", "sdb", "sdc", "sdd", "sde", "sdf", "sdg", "sdh", "sdi", "sdj"],
        },
    },
    "TrueNAS-CORE": {
        "system_info": {
            "system_os": "TrueNAS CORE",
            "ipmi_type": "SM_X10",
            "single_zone": True,
            "temp_focus": "Both",
            "disks": ["da0", "da1", "da2", "da3", "da4", "da5", "da6", "da7", "da8", "da9", "da10", "da11", "da12", "da13"],
        },
    },
    "pfSense": {
        "system_info": {
            "system_os": "pfSense",
            "ipmi_type": "SM_X10",
            "single_zone": True,
            "temp_focus": "CPU",
            "disks": ["da0", "da1", "da2", "da3", "da4", "da5", "da6", "da7", "da8", "da9", "da10", "da11", "da12", "da13"],
        },
        "fan_curve": {
            "cpu": [
                [0, 0],
                [25, 20],
                [35, 20],
                [40, 20],
                [45, 30],
                [50, 40],
                [60, 50],
                [70, 60],
                [80, 100],
                [90, 100],
                [100, 100],
            ],
            "hdd": [
                [0, 0],
                [25, 20],
                [35, 25],
                [40, 30],
                [45, 35],
                [50, 40],
                [60, 50],
                [70, 70],
                [80, 80],
                [90, 100],
                [100, 100],
            ],
        },
        "hdd_panic": {
            "max_temp": 42,
            "panic_addition": 15,
        },
    },
}

SYSTEM_OS_TO_PROFILE = {
    "Proxmox": "Proxmox",
    "TrueNAS CORE": "TrueNAS-CORE",
    "pfSense": "pfSense",
}


def toml_literal(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list):
        return "[{}]".format(", ".join(toml_literal(item) for item in value))
    raise TypeError("Unsupported TOML value: {!r}".format(value))


def write_table(lines, table_name, values):
    lines.append("[{}]".format(table_name))
    for key, value in values.items():
        lines.append("{} = {}".format(key, toml_literal(value)))
    lines.append("")


def merge_nested_dict(base, overrides):
    merged = copy.deepcopy(base)
    for key, value in overrides.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = merge_nested_dict(merged[key], value)
        else:
            merged[key] = copy.deepcopy(value)
    return merged


def read_existing_profile():
    if not os.path.exists(CONFIG_PATH):
        return None

    with open(CONFIG_PATH, "rb") as config_file:
        existing_config = tomllib.load(config_file)

    system_os = existing_config.get("system_info", {}).get("system_os")
    return SYSTEM_OS_TO_PROFILE.get(system_os)


def build_config(profile_name):
    return merge_nested_dict(COMMON_CONFIG, PROFILE_OVERRIDES[profile_name])


def resolve_profile(cli_profile):
    if cli_profile:
        return cli_profile

    existing_profile = read_existing_profile()
    if existing_profile:
        return existing_profile

    return DEFAULT_PROFILE


def main():
    parser = argparse.ArgumentParser(
        description="Generate config.toml for fan-control")
    parser.add_argument("--profile", choices=sorted(PROFILE_OVERRIDES.keys()))
    args = parser.parse_args()

    profile_name = resolve_profile(args.profile)
    config_object = build_config(profile_name)

    lines = ["# Generated by gen-config.py",
             "# Active profile: {}".format(profile_name), ""]
    write_table(lines, "system_info", config_object["system_info"])
    write_table(lines, "fan_curve", config_object["fan_curve"])
    write_table(lines, "hdd_panic", config_object["hdd_panic"])
    write_table(lines, "detect_timers", config_object["detect_timers"])
    write_table(lines, "log_config", config_object["log_config"])

    with open(CONFIG_PATH, "w", encoding="utf-8") as conf:
        conf.write("\n".join(lines).rstrip() + "\n")

    print("Configuration file successfully written for profile: {}".format(profile_name))


if __name__ == "__main__":
    main()
