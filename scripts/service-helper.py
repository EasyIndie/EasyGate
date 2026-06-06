#!/usr/bin/env python3
"""EasyGate service helper — add/remove/list services in Traefik dynamic YAML."""

import sys, re


def get_indent(line):
    """Return indentation level (number of leading spaces)."""
    return len(line) - len(line.lstrip(" "))


def get_section_boundaries(lines):
    """Find start and end of routers and services sections."""
    routers_start = services_start = -1
    for i, line in enumerate(lines):
        s = line.rstrip()
        if s in ("  routers:", "  routers: {}"):
            routers_start = i
        elif s in ("  services:", "  services: {}"):
            services_start = i
    return routers_start, services_start


def find_entries(lines, section_start):
    """Find entries in a YAML section (names of 4-space indented blocks)."""
    entries = {}
    if section_start < 0:
        return entries
    i = section_start + 1
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        indent = get_indent(line)
        if indent == 4 and line.rstrip().endswith(":"):
            name = line.strip()[:-1]
            # Find end of this entry
            j = i + 1
            while j < len(lines) and (get_indent(lines[j]) > 4 or not lines[j].strip()):
                j += 1
            entries[name] = (i, j)
            i = j
        elif indent <= 2:  # New top-level section
            break
        else:
            i += 1
    return entries


def list_services(path):
    try:
        with open(path) as f:
            lines = f.readlines()
    except FileNotFoundError:
        print("暂无已配置的服务")
        return

    routers_start, services_start = get_section_boundaries(lines)
    routers = find_entries(lines, routers_start)
    services = find_entries(lines, services_start)

    # Merge router and service info
    all_svcs = {}
    for name, (start, end) in routers.items():
        info = {"host": "?", "url": "?"}
        for i in range(start, end):
            s = lines[i].strip()
            m = re.search(r"Host\(`([^)]+)`\)", s)
            if m:
                info["host"] = m.group(1)
            if s.startswith("service: ") and s != f"service: api@internal":
                pass  # URL comes from services section
        all_svcs[name] = info

    for name, (start, end) in services.items():
        info = all_svcs.get(name, {"host": "?", "url": "?"})
        all_svcs[name] = info
        for i in range(start, end):
            s = lines[i].strip()
            if s.startswith("- url:"):
                info["url"] = s.split("- url:", 1)[1].strip()

    if all_svcs:
        print(f"{'Name':<20} {'Host':<35} {'URL'}")
        print("-" * 80)
        for name in sorted(all_svcs):
            info = all_svcs[name]
            print(f"{name:<20} {info.get('host', '?'):<35} {info.get('url', '?')}")
    else:
        print("暂无已配置的服务")


def add_service(path, name, host, url):
    try:
        with open(path) as f:
            lines = f.readlines()
    except FileNotFoundError:
        lines = ["http:\n", "  routers: {}\n", "  services: {}\n"]

    routers_start, services_start = get_section_boundaries(lines)

    # Check duplicate
    routers = find_entries(lines, routers_start)
    if name in routers:
        print(f"[easygate] 服务 {name} 已存在", file=sys.stderr)
        sys.exit(1)

    # Fix "{}" placeholders
    for i, line in enumerate(lines):
        if line.rstrip() == "  routers: {}":
            lines[i] = "  routers:\n"
        elif line.rstrip() == "  services: {}":
            lines[i] = "  services:\n"

    router_block = [
        f"    {name}:\n",
        f"      rule: Host(`{host}`)\n",
        f"      entryPoints:\n",
        f"        - web\n",
        f"      service: {name}\n",
    ]
    service_block = [
        f"    {name}:\n",
        f"      loadBalancer:\n",
        f"        servers:\n",
        f"          - url: {url}\n",
    ]

    routers_start, services_start = get_section_boundaries(lines)

    if services_start >= 0:
        # Insert router before services section
        for item in reversed(router_block):
            lines.insert(services_start, item)
        # Insert service at end of services section
        routers_start, services_start = get_section_boundaries(lines)
        j = services_start + 1
        while j < len(lines) and (get_indent(lines[j]) >= 4 or not lines[j].strip()):
            j += 1
        for item in reversed(service_block):
            lines.insert(j, item)
    else:
        lines.append("\n")
        lines.extend(router_block)
        lines.append("  services:\n")
        lines.extend(service_block)

    with open(path, "w") as f:
        f.writelines(lines)
    print(f"[easygate] 已添加服务：{name} → {host} → {url}")


def remove_service(path, name):
    with open(path) as f:
        lines = f.readlines()

    routers_start, services_start = get_section_boundaries(lines)
    routers = find_entries(lines, routers_start)
    services = find_entries(lines, services_start)

    removed = False

    # Remove from routers section
    if name in routers:
        start, end = routers[name]
        # Remove lines including any trailing blank line
        while end < len(lines) and not lines[end].strip():
            end += 1
        for i in range(end - 1, start - 1, -1):
            del lines[i]
        removed = True

    # Remove from services section
    routers_start, services_start = get_section_boundaries(lines)
    services = find_entries(lines, services_start)
    if name in services:
        start, end = services[name]
        while end < len(lines) and not lines[end].strip():
            end += 1
        for i in range(end - 1, start - 1, -1):
            del lines[i]
        removed = True

    if not removed:
        print(f"[easygate] 未找到服务：{name}", file=sys.stderr)
        sys.exit(0)

    with open(path, "w") as f:
        f.writelines(lines)
    print(f"[easygate] 已删除服务：{name}")


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "add":
        add_service(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    elif cmd == "remove":
        remove_service(sys.argv[2], sys.argv[3])
    elif cmd == "list":
        list_services(sys.argv[2])
    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)
