#!/bin/bash
# Test Kustomize configuration before deploying

set -e

echo "🔍 Testing Kustomize Configuration..."
echo ""

# Check if kustomize is installed
if ! command -v kustomize &> /dev/null; then
    echo "❌ kustomize not found. Installing..."
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    sudo mv kustomize /usr/local/bin/
fi

echo "✅ Kustomize version: $(kustomize version --short)"
echo ""

# Test build
echo "🔨 Building overlays/production..."
cd "$(git rev-parse --show-toplevel)/overlays/production"

if kustomize build . > /tmp/kustomize-output.yaml 2>&1; then
    echo "✅ Build successful!"
    echo ""

    # Count resources
    RESOURCE_COUNT=$(grep -c "^kind:" /tmp/kustomize-output.yaml || true)
    echo "📊 Resources generated: $RESOURCE_COUNT"
    echo ""

    # Show Applications
    echo "📱 ArgoCD Applications:"
    grep "name:" /tmp/kustomize-output.yaml | grep -v "metadata:" | head -20
    echo ""

    # Validate with kubectl
    echo "🔍 Validating with kubectl..."
    if kubectl apply --dry-run=client -f /tmp/kustomize-output.yaml &> /dev/null; then
        echo "✅ kubectl validation passed (client-side)"
    else
        echo "⚠️  kubectl validation failed (client-side)"
        echo "Run: kubectl apply --dry-run=client -f /tmp/kustomize-output.yaml"
    fi
    echo ""

    # Show enabled components
    echo "🎯 Enabled Components:"
    grep "^  - ../../components" overlays/production/kustomization.yaml | grep -v "^#" | sed 's/.*components\//  ✓ /' || echo "  (none found)"
    echo ""

    # Show disabled components
    echo "💤 Disabled Components:"
    grep "^#.*- ../../components" overlays/production/kustomization.yaml | sed 's/.*components\//  ✗ /' || echo "  (none found)"
    echo ""

    echo "💾 Full output saved to: /tmp/kustomize-output.yaml"
    echo ""
    echo "To review: cat /tmp/kustomize-output.yaml"
    echo "To deploy: git add . && git commit -m 'Update Kustomize config' && git push"

else
    echo "❌ Build failed!"
    echo ""
    cat /tmp/kustomize-output.yaml
    exit 1
fi
