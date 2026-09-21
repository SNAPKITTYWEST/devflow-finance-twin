#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
"""Canvas processor: XML + XSLT -> LaTeX + Swift stubs + optional PDF."""
from __future__ import annotations
import argparse, re, subprocess, sys
from pathlib import Path
from lxml import etree

def slug(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_")

def transform(xml_path: Path, xslt_path: Path) -> tuple[etree._ElementTree, str]:
    xml = etree.parse(str(xml_path))
    xslt = etree.XSLT(etree.parse(str(xslt_path)))
    result = xslt(xml)
    return xml, str(result)

def validate_tree(xml: etree._ElementTree) -> bool:
    ok = True
    print("Validating architecture tree")
    for layer in xml.xpath("//architecture//layer"):
        name = layer.get("name") or ""
        children = list(layer.xpath("./layer"))
        print(f"  - {name} ({len(children)} children)")
        if not name.strip():
            print("    warning: layer missing name")
            ok = False
    return ok

def holes(xml: etree._ElementTree) -> list[dict[str, str]]:
    out = []
    for hole in xml.xpath("//swift-stub/hole"):
        expected = hole.findtext("expected") or ""
        placeholder = hole.findtext("placeholder") or ""
        out.append({"id": hole.get("id", ""), "description": hole.get("description", ""), "type": hole.get("type", ""), "expected": expected.strip(), "placeholder": placeholder.strip()})
    return out

def signatures(xml: etree._ElementTree) -> list[dict]:
    sigs = []
    for stub in xml.xpath("//swift-stub"):
        sig = stub.find("signature")
        if sig is None: continue
        params = [f"{p.get('name')}: {p.get('type')}" for p in sig.xpath("./param")]
        sigs.append({"access": sig.get("access", "internal"), "name": sig.get("name", "untitled"), "returns": sig.get("returns", "Void"), "async": sig.get("async") == "true", "throws": sig.get("throws") == "true", "params": params, "holes": [{"id": h.get("id", ""), "description": h.get("description", ""), "type": h.get("type", ""), "expected": (h.findtext("expected") or "").strip(), "placeholder": (h.findtext("placeholder") or "").strip()} for h in stub.xpath("./hole")]})
    return sigs

def write_swift(canvas_name: str, sigs: list[dict], dest: Path) -> None:
    lines = [f"// Auto-generated from Canvas: {canvas_name}", "// Fill the holes. fatalError markers must not ship.", "", "import Foundation", ""]
    for sig in sigs:
        mods = []
        if sig["async"]: mods.append("async")
        if sig["throws"]: mods.append("throws")
        ret = "" if sig["returns"] == "Void" else f" -> {sig['returns']}"
        header = f"{sig['access']} func {sig['name']}({', '.join(sig['params'])}) {' '.join(mods)}{ret} {{"
        lines.append(header)
        for hole in sig["holes"]:
            lines.append(f"    // HOLE[{hole['id']}]: {hole['description']}")
            lines.append(f"    // Type: {hole['type']}")
            lines.append(f"    // Expected: {hole['expected']}")
            lines.append(f"    {hole['placeholder']}")
            ident = re.sub(r"[^A-Za-z0-9_]", "_", hole["id"])
            lines.append(f"    fatalError(\"Implement HOLE[{ident}]\")")
            lines.append("")
        lines.append("}")
        lines.append("")
    dest.write_text("\n".join(lines), encoding="utf-8")

def compile_pdf(tex: Path, out_dir: Path) -> Path | None:
    cmd = ["pdflatex", "-interaction=nonstopmode", "-halt-on-error", f"-output-directory={out_dir}", str(tex)]
    run = subprocess.run(cmd, capture_output=True, text=True)
    pdf = out_dir / (tex.stem + ".pdf")
    if run.returncode != 0 or not pdf.exists():
        log = out_dir / (tex.stem + ".log")
        tail = log.read_text(errors="replace")[-2000:] if log.exists() else run.stderr
        print("pdflatex failed:\n", tail)
        return None
    subprocess.run(cmd, capture_output=True, text=True)
    return pdf

def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--xml", required=True)
    p.add_argument("--xslt", required=True)
    p.add_argument("--out", default="./output")
    p.add_argument("--swift", action="store_true")
    p.add_argument("--validate", action="store_true")
    p.add_argument("--pdf", action="store_true")
    args = p.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    xml, latex = transform(Path(args.xml), Path(args.xslt))
    name = xml.getroot().get("name") or "canvas"
    tex = out / f"{slug(name)}.tex"
    tex.write_text(latex, encoding="utf-8")
    print(f"LaTeX: {tex}")
    if args.validate: validate_tree(xml)
    if args.swift:
        swift_path = out / f"{slug(name)}_Stubs.swift"
        write_swift(name, signatures(xml), swift_path)
        print(f"Swift: {swift_path}")
        for hole in holes(xml):
            print(f"  [{hole['id']}] {hole['description']} -> {hole['type']}")
    if args.pdf:
        pdf = compile_pdf(tex, out)
        if pdf: print(f"PDF: {pdf}")
        else: return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
