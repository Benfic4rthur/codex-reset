#!/usr/bin/env python3
"""Display the latest published GitHub Release beside the README downloads."""
import argparse
import json
from pathlib import Path
import re
import subprocess

START = "<!-- latest-release:start -->"
END = "<!-- latest-release:end -->"


def download_section(repository, release, expected_version):
    tag = release["tag_name"]
    version = tag.removeprefix("v")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or version != expected_version:
        raise ValueError("A última Release publicada não corresponde à versão esperada.")
    if release["draft"] or release["prerelease"]:
        raise ValueError("A versão de download precisa ser uma Release estável publicada.")
    assets = {asset["name"] for asset in release["assets"] if asset["state"] == "uploaded"}
    if not {"Codex-Reset-Apple-Silicon.dmg", "Codex-Reset-Intel.dmg", "SHA256SUMS.txt"} <= assets:
        raise ValueError("A Release ainda não tem os dois DMGs e seus hashes publicados.")
    base = f"https://github.com/{repository}/releases"
    return f"""{START}
### Versão atual: [{version}]({base}/tag/{tag})

Os dois downloads abaixo são da **versão {version}**. [Ver novidades desta versão]({base}/tag/{tag}).

| Apple Silicon · M1, M2, M3 e posteriores | Intel · x86_64 |
| :---: | :---: |
| **[⬇ Baixar Apple Silicon · {version}]({base}/latest/download/Codex-Reset-Apple-Silicon.dmg)** | **[⬇ Baixar Intel · {version}]({base}/latest/download/Codex-Reset-Intel.dmg)** |
| Com notch: visual integrado ao recorte. Sem notch, incluindo M1: cápsula no topo | Cápsula compacta dentro da barra de menus |
{END}"""


def update_readme(readme, section):
    text = readme.read_text()
    if text.count(START) != 1 or text.count(END) != 1:
        raise ValueError("O README precisa ter exatamente um bloco de downloads marcado.")
    start = text.index(START)
    end = text.index(END, start) + len(END)
    updated = text[:start] + section + text[end:]
    if updated != text:
        readme.write_text(updated)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--expected-version", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repository):
        parser.error("Repositório inválido.")
    release = json.loads(subprocess.check_output(
        ["gh", "api", f"repos/{args.repository}/releases/latest"], text=True))
    section = download_section(args.repository, release, args.expected_version)
    update_readme(Path(__file__).resolve().parent.parent / "README.md", section)
    print(f"Downloads identificados como versão {args.expected_version}.")


if __name__ == "__main__":
    main()
