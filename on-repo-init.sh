#!/bin/sh

HOOKS_DIR=.git/hooks
PRE_COMMIT_GIT_HOOK_PATH=$HOOKS_DIR/pre-commit

mkdir -p $HOOKS_DIR
mkdir -p BuildTools

cat > $PRE_COMMIT_GIT_HOOK_PATH <<'EOF'
#!/bin/sh

./swiftformat-staged.sh
EOF

chmod +x $PRE_COMMIT_GIT_HOOK_PATH

## Install Swift Format
echo "Preparing to install swiftformat to BuildTools/.build/release/swiftformat"
swift build -c release --package-path BuildTools --product swiftformat
