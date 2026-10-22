#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
output_dir="$project_dir/.build/releases/$version"
mkdir -p "$output_dir"
work_dir="$(mktemp -d "$project_dir/.build/dmg-work.XXXXXX")"
mounted_dir=''
cleanup() {
    if [[ -n "$mounted_dir" ]]; then
        hdiutil detach "$mounted_dir" >/dev/null || return
    fi
    rm -R -- "$work_dir"
}
trap cleanup EXIT

for architecture in arm64 x86_64; do
    if [[ "$architecture" == arm64 ]]; then
        variant='Apple-Silicon'
        display_name='Apple Silicon'
    else
        variant='Intel'
        display_name='Intel'
    fi
    volume_dir="$work_dir/$variant"
    app_dir="$volume_dir/Codex Reset.app"
    mkdir -p "$volume_dir"
    "$project_dir/scripts/build-app.sh" --arch "$architecture" --output "$app_dir"
    python3 "$project_dir/scripts/audit-distribution.py" "$app_dir"
    ln -s /Applications "$volume_dir/Aplicativos"
    cat > "$volume_dir/Leia-me.txt" <<TEXT
Codex Reset $version — $display_name

Requisitos: macOS 14 ou mais recente e Codex Desktop instalado e autenticado.

1. Arraste Codex Reset.app para a pasta Aplicativos.
2. Se estiver atualizando, feche o Codex Reset e substitua o aplicativo anterior.
3. Execute no Terminal o comando de liberação abaixo antes da primeira abertura.
4. Abra o Codex Reset uma vez. O início automático será configurado para este usuário.
5. O monitor aparece enquanto o Codex Desktop está aberto.

Macs com notch: visual integrado ao recorte.
MacBooks Intel e M1 sem notch: cápsula compacta inteira dentro da barra de menus,
com porcentagem grande e uma barra horizontal de progresso separada. A altura é
medida pelo macOS na própria tela, com uma pequena margem para o contorno.
Projeto, modelo e esforço aparecem em uma linha quando há atividade.
O reset semanal mostra dias e horas; nas últimas 24 horas, mostra horas e minutos.
O reset extra indica a faixa com "Entre ... e ..." e "Estimativa histórica".
O histórico usa somente os últimos 30 dias e é consultado ao abrir e a cada duas horas.
Com seis a onze intervalos, a estimativa é identificada como amostra pequena.
A contagem regressiva atualiza localmente a cada minuto, sem consultar o site.
Uma janela extra encerrada aguarda novos dados.

Esta distribuição ainda não tem assinatura Developer ID nem notarização da Apple.
O macOS pode bloquear a abertura até você autorizar o aplicativo.
Após copiar o app para Aplicativos, cole no Terminal:

if [ -d "/Applications/Codex Reset.app" ]; then
  xattr -dr com.apple.quarantine "/Applications/Codex Reset.app"
elif [ -d "\$HOME/Applications/Codex Reset.app" ]; then
  xattr -dr com.apple.quarantine "\$HOME/Applications/Codex Reset.app"
else
  echo "Copie primeiro o Codex Reset.app do DMG para a pasta Aplicativos."
fi

Depois, abra o Codex Reset e o Codex Desktop.
Repita a liberação ao instalar uma nova versão baixada. Orientações da Apple:
https://support.apple.com/102445

Downloads e novas versões:
https://github.com/Benfic4rthur/codex-reset/releases/latest
TEXT
    if [[ "$(< "$volume_dir/Leia-me.txt")" == *"$HOME/"* ]]; then
        print -u2 'As instruções de instalação contêm um caminho pessoal.'
        exit 1
    fi
    dmg="$output_dir/Codex-Reset-$variant.dmg"
    hdiutil create -volname "Codex Reset $version $display_name" \
        -srcfolder "$volume_dir" -fs HFS+ -format UDZO -ov "$dmg"
    hdiutil verify "$dmg"
    mounted_dir="$work_dir/mounted"
    mkdir -p "$mounted_dir"
    hdiutil attach "$dmg" -readonly -nobrowse -mountpoint "$mounted_dir" >/dev/null
    mounted_app="$mounted_dir/Codex Reset.app"
    codesign --verify --deep --strict "$mounted_app"
    python3 "$project_dir/scripts/audit-distribution.py" "$mounted_app"
    for executable in CodexReset CodexResetCompanion; do
        [[ "$(lipo -archs "$mounted_app/Contents/MacOS/$executable")" == "$architecture" ]]
    done
    [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$mounted_app/Contents/Info.plist")" == "$version" ]]
    [[ "$(readlink "$mounted_dir/Aplicativos")" == /Applications ]]
    hdiutil detach "$mounted_dir" >/dev/null
    rmdir "$mounted_dir"
    mounted_dir=''
done

(
    cd "$output_dir"
    shasum -a 256 Codex-Reset-Apple-Silicon.dmg Codex-Reset-Intel.dmg > SHA256SUMS.txt
    shasum -a 256 -c SHA256SUMS.txt
)
print -r -- "DMGs gerados: $output_dir"
