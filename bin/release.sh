#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# ── Versão ────────────────────────────────────────────────────────────────────

VERSION=$(ruby -Ilib -e 'require "json2sql/version"; puts Json2sql::VERSION')
GEM_FILE="pkg/json2sql-${VERSION}.gem"
TAG="v${VERSION}"

echo "==> json2sql ${VERSION}"

# ── Testes ────────────────────────────────────────────────────────────────────

echo "==> A correr testes..."
ruby -Ilib test/json2sql_test.rb

# ── Verificar tag git ─────────────────────────────────────────────────────────

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "ERRO: a tag ${TAG} já existe." >&2
  exit 1
fi

# ── Confirmação ───────────────────────────────────────────────────────────────

echo ""
read -rp "Publicar json2sql ${VERSION} no RubyGems? [s/N] " confirm
if [[ "${confirm,,}" != "s" ]]; then
  echo "Cancelado."
  exit 0
fi

# ── Build ─────────────────────────────────────────────────────────────────────

mkdir -p pkg
echo "==> A compilar gem..."
gem build json2sql.gemspec --output "$GEM_FILE"

# ── Tag git ───────────────────────────────────────────────────────────────────

echo "==> A criar tag ${TAG}..."
git tag "$TAG"

# ── Publicar ──────────────────────────────────────────────────────────────────

echo "==> A publicar ${GEM_FILE}..."
gem push "$GEM_FILE"

# ── Push git ──────────────────────────────────────────────────────────────────

echo "==> A fazer push da tag..."
git push origin "$TAG"

echo ""
echo "==> json2sql ${VERSION} publicado com sucesso."
