#!/usr/bin/env python3
"""生成 App 图标。

设计意图：主体是一株实心仙人掌，身后错开一个半透明的「虚影」——
正是 App 的核心功能（幽灵叠影对齐），同时也读作「同一株植物的前后对比」。

改完直接跑：python3 Tools/make_app_icon.py
"""

from PIL import Image, ImageDraw

SIZE = 1024
OUT = "Thrive/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

BG_TOP = (52, 116, 73)       # 深绿
BG_BOTTOM = (24, 68, 43)     # 更深的绿，做竖向渐变
CACTUS = (242, 238, 226)     # 米白
GHOST = (242, 238, 226, 64)  # 半透明虚影
POT = (203, 124, 84)
POT_RIM = (222, 143, 100)

# 版面：iOS 会把四角切成圆角。整组（仙人掌 + 花盆）的视觉重心要落在画布正中，
# 所以土面定得比几何中心高一截，剩下的空间留给花盆。
SOIL_Y = 640          # 土面高度，仙人掌从这里往上长
CENTER_X = 512
GROUP = 1.12          # 整组缩放，让主体占到画面约 65%


def cactus(draw, cx, base, scale, fill):
    """一株仙人掌：主干 + 左右两条侧枝（右边高一点，避免对称呆板）。"""
    body_h = int(400 * scale)
    body_w = int(170 * scale)
    arm_w = int(112 * scale)
    arm_h = int(200 * scale)
    gap = int(26 * scale)

    draw.rounded_rectangle(
        [cx - body_w // 2, base - body_h, cx + body_w // 2, base],
        radius=body_w // 2, fill=fill,
    )
    left = cx - body_w // 2 - gap - arm_w
    draw.rounded_rectangle(
        [left, base - body_h + int(170 * scale), left + arm_w, base - body_h + int(170 * scale) + arm_h],
        radius=arm_w // 2, fill=fill,
    )
    right = cx + body_w // 2 + gap
    draw.rounded_rectangle(
        [right, base - body_h + int(115 * scale), right + arm_w, base - body_h + int(115 * scale) + arm_h],
        radius=arm_w // 2, fill=fill,
    )


def main():
    img = Image.new("RGB", (SIZE, SIZE), BG_TOP)
    d = ImageDraw.Draw(img)

    for y in range(SIZE):
        t = y / SIZE
        d.line(
            [(0, y), (SIZE, y)],
            fill=tuple(int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3)),
        )

    # 虚影先画：小一号、往左错开，代表「上一次的它」
    ghost = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    cactus(ImageDraw.Draw(ghost), CENTER_X - 78, SOIL_Y, 0.78 * GROUP, GHOST)
    img.paste(ghost, (0, 0), ghost)

    d = ImageDraw.Draw(img)
    cactus(d, CENTER_X + 22, SOIL_Y, GROUP, CACTUS)

    # 花盆：上宽下窄的梯形 + 盆沿，整体收窄，别抢主体
    def s(v):
        return int(v * GROUP)

    pot_top_y = SOIL_Y + s(6)
    pot_bottom_y = SOIL_Y + s(190)
    d.polygon(
        [(CENTER_X - s(172), pot_top_y), (CENTER_X + s(172), pot_top_y),
         (CENTER_X + s(132), pot_bottom_y), (CENTER_X - s(132), pot_bottom_y)],
        fill=POT,
    )
    d.rounded_rectangle(
        [CENTER_X - s(196), SOIL_Y - s(34), CENTER_X + s(196), pot_top_y + s(14)],
        radius=s(22), fill=POT_RIM,
    )

    img.save(OUT)
    print(f"wrote {OUT} ({SIZE}x{SIZE})")


if __name__ == "__main__":
    main()
