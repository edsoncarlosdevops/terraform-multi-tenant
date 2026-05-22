#!/bin/bash
# ─── Script de Versionamento Local ───────────────────────────
# Uso: ./scripts/version.sh
#
# Cria tags SemVer automáticas baseadas nos commits
# Exibe a versão atual para usar no terraform apply

set -euo pipefail

get_last_tag() {
  git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0"
}

get_next_version() {
  local LAST_TAG=$1
  local MAJOR=$(echo "$LAST_TAG" | cut -d. -f1 | tr -d 'v')
  local MINOR=$(echo "$LAST_TAG" | cut -d. -f2)
  local PATCH=$(echo "$LAST_TAG" | cut -d. -f3)
  echo "v$MAJOR.$MINOR.$((PATCH + 1))"
}

get_commit_hash() {
  git rev-parse --short HEAD
}

case "${1:-help}" in
  current)
    echo "📌 Versão atual: $(get_last_tag)"
    echo "🔑 Commit:       $(get_commit_hash)"
    ;;

  next)
    LAST_TAG=$(get_last_tag)
    NEXT_TAG=$(get_next_version "$LAST_TAG")
    echo "📌 Última tag:  $LAST_TAG"
    echo "📦 Próxima tag: $NEXT_TAG"
    echo ""
    echo "Para aplicar com essa versão:"
    echo "  export TF_VAR_infra_version=$NEXT_TAG"
    echo "  terraform apply"
    ;;

  tag)
    LAST_TAG=$(get_last_tag)
    NEXT_TAG=$(get_next_version "$LAST_TAG")
    echo "🏷️  Criando tag $NEXT_TAG..."
    git tag -a "$NEXT_TAG" -m "Release $NEXT_TAG"
    git push origin "$NEXT_TAG"
    echo "✅ Tag $NEXT_TAG criada e enviada!"
    ;;

  help|*)
    echo "Uso: ./scripts/version.sh <comando>"
    echo ""
    echo "Comandos:"
    echo "  current    Mostra a versão atual e commit"
    echo "  next       Mostra qual será a próxima versão"
    echo "  tag        Cria e envia a próxima tag"
    ;;
esac
