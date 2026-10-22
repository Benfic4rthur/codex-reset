#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
if [[ -n "$(git status --porcelain)" ]]; then
    print -u2 'Faça o commit das alterações antes de publicar uma versão.'
    exit 1
fi
if [[ -n "$(git ls-files .github/workflows)" ]]; then
    print -u2 'Este projeto não usa GitHub Actions. Remova os workflows antes de publicar.'
    exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
tag="v$version"
notes="$project_dir/releases/$tag.md"
[[ -f "$notes" ]] || { print -u2 "Crie as notas da versão em releases/$tag.md."; exit 1; }
repository="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
if [[ "$(gh api "repos/$repository/actions/permissions" --jq '.enabled')" != false ]]; then
    print -u2 'O GitHub Actions precisa estar desativado nas configurações do repositório.'
    exit 1
fi
if gh release view "$tag" --repo "$repository" >/dev/null 2>&1; then
    print -u2 "A versão $tag já existe. Incremente a versão para publicar uma nova."
    exit 1
fi

"$project_dir/scripts/create-dmgs.sh"
python3 "$project_dir/scripts/audit-distribution.py" --git-history
output_dir="$project_dir/.build/releases/$version"
commit="$(git rev-parse HEAD)"
git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push origin HEAD
gh release create "$tag" \
    "$output_dir/Codex-Reset-Apple-Silicon.dmg" \
    "$output_dir/Codex-Reset-Intel.dmg" \
    "$output_dir/SHA256SUMS.txt" \
    --repo "$repository" --target "$commit" --title "Codex Reset $version" \
    --notes-file "$notes" --draft
asset_names="$(gh release view "$tag" --repo "$repository" --json assets --jq '.assets[].name' | sort)"
expected_names="$(printf '%s\n' Codex-Reset-Apple-Silicon.dmg Codex-Reset-Intel.dmg SHA256SUMS.txt | sort)"
[[ "$asset_names" == "$expected_names" ]] || {
    print -u2 'Os arquivos da versão estão incompletos. A release foi mantida como rascunho.'
    exit 1
}
gh release edit "$tag" --repo "$repository" --draft=false --latest
python3 "$project_dir/scripts/update-downloads.py" --repository "$repository" --expected-version "$version"
if ! git diff --quiet -- README.md; then
    git add README.md
    git commit -m "docs: show $version as the current download version"
    git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push origin HEAD
fi
gh release view "$tag" --repo "$repository" --json url --jq '.url'
