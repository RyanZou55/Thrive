#!/bin/bash
#
# 发版前置：把工作区对到 main 最新，核对版本号，可选直接打包。
#
#   Tools/release-preflight.sh            只检查和更新，不打包
#   Tools/release-preflight.sh --archive  检查通过后顺带 Archive
#
# 只能在 Mac 上跑（打包那步要 Xcode）。

set -uo pipefail

EXPECT_VERSION="1.3.2"
EXPECT_BUILD="7"

cd "$(dirname "$0")/.." || exit 1
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "❌ 这不是个 git 仓库"; exit 1; }
cd "$ROOT" || exit 1

echo "仓库目录：$ROOT"
echo "当前分支：$(git branch --show-current)"
echo "当前提交：$(git log --oneline -1)"
echo

# 有未提交的改动就停下 —— 那可能是还没进仓库的工作，不能替你处理掉。
if [ -n "$(git status --porcelain)" ]; then
    echo "❌ 工作区有未提交的改动，先处理掉再来："
    git status --short
    echo
    echo "   想留着：git stash push -m '发版前暂存'"
    echo "   确定不要：git checkout -- .   ← 不可恢复，想清楚"
    exit 1
fi

echo "→ 拉取 main"
git fetch origin main || { echo "❌ fetch 失败，检查网络"; exit 1; }
git checkout main || exit 1
git pull --ff-only origin main || {
    echo "❌ 不能快进合并 —— 本地 main 有远端没有的提交。把它们推上去或另开分支。"
    exit 1
}
echo "   现在是：$(git log --oneline -1)"
echo

PBX="Thrive.xcodeproj/project.pbxproj"
VERSION="$(grep -m1 'MARKETING_VERSION' "$PBX" | sed 's/.*= *//;s/;//')"
BUILD="$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBX" | sed 's/.*= *//;s/;//')"
echo "项目文件里的版本号：$VERSION ($BUILD)"

if [ "$VERSION" != "$EXPECT_VERSION" ] || [ "$BUILD" != "$EXPECT_BUILD" ]; then
    echo "❌ 期望 $EXPECT_VERSION ($EXPECT_BUILD)，实际 $VERSION ($BUILD)"
    echo "   如果这个目录不是 Xcode 打开的那个，去 Xcode 里右键项目 → Show in Finder 对一下。"
    exit 1
fi
echo "✅ 版本号对上了"
echo

cat <<'NOTE'
────────────────────────────────────────────────────────
打包之前，这一步别跳过：

  手机连上 → Xcode 设备选你的 iPhone → ⌘R 覆盖装（别删旧版）
  → 打开一条 1.2 或 1.3 拍的转盘记录详情页

这版新增了 GrowthEntry.spinPhotoIndex，是转盘上线以来第一次
SwiftData 迁移。全新安装 100% 测不出问题，崩就崩在这个页面。
────────────────────────────────────────────────────────
NOTE

if [ "${1:-}" != "--archive" ]; then
    echo "只做了检查。确认迁移没问题后，用 --archive 再跑一次，或者在 Xcode 里手动 Archive。"
    exit 0
fi

echo "→ 清理并打包"
DEST="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
mkdir -p "$DEST"
xcodebuild -project Thrive.xcodeproj -scheme Thrive -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$DEST/Thrive $VERSION ($BUILD).xcarchive" \
    clean archive || {
        echo
        echo "❌ 打包失败。上面的报错发我。"
        echo "   scheme 名字不对的话，跑 xcodebuild -list 看看实际叫什么。"
        exit 1
    }

echo
echo "✅ 打包完成，已放进 Organizer 能看到的位置。"
echo "   Xcode → Window → Organizer → Archives，确认最上面那个是 $VERSION ($BUILD)"
echo "   再点 Distribute App → App Store Connect → Upload。"
