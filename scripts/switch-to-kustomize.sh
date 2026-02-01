#!/bin/bash
# Switch ArgoCD root application to use Kustomize

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
CURRENT_ROOT="$REPO_ROOT/bootstrap/root.yaml"
KUSTOMIZE_ROOT="$REPO_ROOT/bootstrap/root-kustomize.yaml"

echo "🔄 Switching ArgoCD root to Kustomize configuration..."
echo ""

# Backup current root
if [ -f "$CURRENT_ROOT" ]; then
    BACKUP="$CURRENT_ROOT.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CURRENT_ROOT" "$BACKUP"
    echo "✅ Backed up current root.yaml to: $(basename $BACKUP)"
fi

# Replace with Kustomize version
cp "$KUSTOMIZE_ROOT" "$CURRENT_ROOT"
echo "✅ Updated root.yaml to use Kustomize overlay"
echo ""

# Show diff
echo "📝 Changes made:"
echo "   Path changed: bootstrap → overlays/production"
echo "   Directory recurse: removed (Kustomize handles it)"
echo ""

# Test the configuration
echo "🧪 Testing Kustomize build..."
cd "$REPO_ROOT/overlays/production"
if kustomize build . > /tmp/kustomize-test.yaml 2>&1; then
    RESOURCE_COUNT=$(grep -c "^kind:" /tmp/kustomize-test.yaml || true)
    echo "✅ Kustomize build successful! ($RESOURCE_COUNT resources)"
else
    echo "❌ Kustomize build failed!"
    cat /tmp/kustomize-test.yaml
    echo ""
    echo "Restoring backup..."
    cp "$BACKUP" "$CURRENT_ROOT"
    exit 1
fi

echo ""
echo "🎯 Next steps:"
echo "   1. Review changes: git diff bootstrap/root.yaml"
echo "   2. Commit: git add bootstrap/root.yaml"
echo "   3. Deploy: git commit -m 'Switch to Kustomize' && git push"
echo ""
echo "⚠️  After pushing, ArgoCD will sync and apply the Kustomize configuration"
echo "    Monitor with: kubectl get applications -n argocd"
