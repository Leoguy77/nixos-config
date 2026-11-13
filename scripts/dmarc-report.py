#!/usr/bin/env python3
"""Summarise gzipped DMARC aggregate reports from a Maildir folder.

Usage: dmarc-report.py [maildir ...]     (default: /var/vmail/.../mail/.DMARC)
       dmarc-report.py --selftest
"""
import email
import email.message
import glob
import gzip
import os
import sys
import tempfile
import xml.etree.ElementTree as ET

DEFAULT = "/var/vmail/lsinfra.de/leon/mail/.DMARC"


def feedback_xml(raw):
    """Yield the decompressed XML of every DMARC report part in an RFC822 message."""
    for part in email.message_from_bytes(raw).walk():
        data = part.get_payload(decode=True) or b""
        if data[:2] == b"\x1f\x8b":
            data = gzip.decompress(data)
        if b"<feedback" in data[:600]:
            yield data


def tag(node):
    return node.tag.rsplit("}", 1)[-1]  # strip the XML namespace


def val(node, path, default="-"):
    child = node.find(path)
    return child.text if child is not None and child.text else default


def summarise(folders):
    rows = {}
    for folder in folders:
        for name in glob.glob(f"{folder}/cur/*") + glob.glob(f"{folder}/new/*"):
            with open(name, "rb") as fh:
                for xml in feedback_xml(fh.read()):
                    root = ET.fromstring(xml)
                    meta = next(c for c in root if tag(c) == "report_metadata")
                    org = val(meta, "org_name")
                    for rec in root:
                        if tag(rec) != "record":
                            continue
                        row = next(c for c in rec if tag(c) == "row")
                        key = (
                            org,
                            val(row, "source_ip"),
                            val(row, "policy_evaluated/disposition"),
                        )
                        agg = rows.setdefault(key, {"n": 0, "dkim": set(), "spf": set()})
                        agg["n"] += int(val(row, "count", "0"))
                        agg["dkim"].add(val(row, "policy_evaluated/dkim"))
                        agg["spf"].add(val(row, "policy_evaluated/spf"))
    return rows


def report(rows):
    out = [f"{'source ip':38} {'count':>5} {'disp':<8} {'dkim':<6} {'spf':<6} org"]
    for (org, ip, disp), agg in sorted(rows.items(), key=lambda kv: -kv[1]["n"]):
        out.append(
            f"{ip:38} {agg['n']:>5} {disp:<8} "
            f"{'/'.join(sorted(agg['dkim'])):<6} "
            f"{'/'.join(sorted(agg['spf'])):<6} {org}"
        )
    total = sum(agg["n"] for agg in rows.values())
    out.append(f"\n{total} messages across {len(rows)} source/disposition pairs")
    return "\n".join(out)


def selftest():
    xml = b"""<?xml version="1.0"?>
<feedback><report_metadata><org_name>example.org</org_name>
<date_range><begin>1</begin><end>2</end></date_range></report_metadata>
<record><row><source_ip>203.0.113.9</source_ip><count>7</count>
<policy_evaluated><disposition>reject</disposition><dkim>fail</dkim><spf>fail</spf>
</policy_evaluated></row></record></feedback>"""
    with tempfile.TemporaryDirectory() as tmp:
        for sub in ("cur", "new"):
            os.makedirs(f"{tmp}/{sub}", exist_ok=True)
        msg = email.message.EmailMessage()
        msg["Subject"] = "Report Domain: lsinfra.de"
        msg.set_content("report attached")
        msg.add_attachment(gzip.compress(xml), maintype="application", subtype="gzip",
                           filename="report.xml.gz")
        with open(f"{tmp}/cur/report.eml", "wb") as fh:
            fh.write(bytes(msg))

        rows = summarise([tmp])
        assert list(rows) == [("example.org", "203.0.113.9", "reject")], rows
        assert rows[("example.org", "203.0.113.9", "reject")]["n"] == 7
        assert rows[("example.org", "203.0.113.9", "reject")]["dkim"] == {"fail"}
    print("selftest ok")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
    else:
        print(report(summarise(sys.argv[1:] or [DEFAULT])))
