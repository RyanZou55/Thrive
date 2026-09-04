#!/bin/bash
#
# 发版前置：把工作区对到 main 最新，核对版本号，可选直接打包。
#
#   Tools/release-preflight.sh            只检查和更新，不打包
#   Tools/release-preflight.sh --archive  检查通过后顺带 Archive
#
# 只能在 Mac 上跑（打包那步要 Xcode）。

set -uo pipefail

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
# 用 FETCH_HEAD 而不是再 pull 一次，省掉重复的 fetch 输出。
git merge --ff-only FETCH_HEAD || {
    echo "❌ 不能快进合并 —— 本地 main 有远端没有的提交。把它们推上去或另开分支。"
    exit 1
}
echo "   现在是：$(git log --oneline -1)"
echo

PBX="Thrive.xcodeproj/project.pbxproj"
read_setting() { grep -m1 "$1" "$2" | sed 's/.*= *//;s/;//'; }

VERSION="$(read_setting MARKETING_VERSION "$PBX")"
BUILD="$(read_setting CURRENT_PROJECT_VERSION "$PBX")"

# 和远端比，而不是写死一个数 —— 下次发版不用回来改脚本。
REMOTE_PBX="$(mktemp)"
git show "origin/main:$PBX" > "$REMOTE_PBX" 2>/dev/null
REMOTE_VERSION="$(read_setting MARKETING_VERSION "$REMOTE_PBX")"
REMOTE_BUILD="$(read_setting CURRENT_PROJECT_VERSION "$REMOTE_PBX")"
rm -f "$REMOTE_PBX"

echo "这个目录里的版本号：$VERSION ($BUILD)"
echo "origin/main 上的：  $REMOTE_VERSION ($REMOTE_BUILD)"

if [ "$VERSION" != "$REMOTE_VERSION" ] || [ "$BUILD" != "$REMOTE_BUILD" ]; then
    echo "❌ 对不上。这个目录多半不是 Xcode 打开的那个 ——"
    echo "   去 Xcode 里右键项目图标 → Show in Finder，看看是不是这里：$ROOT"
    exit 1
fi
echo "✅ 版本号和远端一致"
echo

cat <<'NOTE'
────────────────────────────────────────────────────────
打包之前，这一步别跳过：

  手机连上 → Xcode 设备选你的 iPhone → ⌘R 覆盖装（别删旧版）
  → ① 能正常启动  ② 打开一条 1.2 或 1.3 拍的转盘记录详情页

这版新增了 GrowthEntry.spinPhotoIndex，是转盘上线以来第一次 SwiftData 迁移。
迁移在建 ModelContainer 那一刻做，失败会走 fatalError —— 所以先看能不能启动，
再看能不能读老记录。全新安装 100% 测不出这类问题。
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
