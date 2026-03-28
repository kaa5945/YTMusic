"""生成 YTMusic App Icon（YouTube Music 風格）"""
from PIL import Image, ImageDraw
import os

def generate_icon(size: int) -> Image.Image:
    """生成指定尺寸的 icon：紅色圓底 + 白色播放三角形"""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 紅色背景圓形（YouTube Music 標誌色 #FF0000）
    padding = int(size * 0.02)
    draw.ellipse(
        [padding, padding, size - padding, size - padding],
        fill=(255, 0, 0, 255),
    )

    # 白色播放三角形（稍微偏右以視覺置中）
    cx = size * 0.52  # 稍微偏右補償視覺
    cy = size * 0.5
    tri_size = size * 0.3

    # 等邊三角形的三個頂點
    points = [
        (cx + tri_size * 0.5, cy),                    # 右
        (cx - tri_size * 0.25, cy - tri_size * 0.45), # 左上
        (cx - tri_size * 0.25, cy + tri_size * 0.45), # 左下
    ]
    draw.polygon(points, fill=(255, 255, 255, 255))

    return img


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.dirname(script_dir)
    resources_dir = os.path.join(project_dir, "build", "YTMusic.app", "Contents", "Resources")
    os.makedirs(resources_dir, exist_ok=True)

    # 生成 1024x1024 主 icon
    icon_1024 = generate_icon(1024)

    # macOS .icns 需要的尺寸
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    images = []
    for s in sizes:
        if s == 1024:
            images.append(icon_1024)
        else:
            images.append(icon_1024.resize((s, s), Image.LANCZOS))

    # 儲存為 iconset 再用 iconutil 轉換
    iconset_dir = os.path.join(project_dir, "build", "AppIcon.iconset")
    os.makedirs(iconset_dir, exist_ok=True)

    icon_sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    for filename, size in icon_sizes:
        resized = icon_1024.resize((size, size), Image.LANCZOS)
        resized.save(os.path.join(iconset_dir, filename))

    # 用 iconutil 轉換成 .icns
    icns_path = os.path.join(resources_dir, "AppIcon.icns")
    os.system(f'iconutil -c icns "{iconset_dir}" -o "{icns_path}"')

    # 清理 iconset
    import shutil
    shutil.rmtree(iconset_dir)

    print(f"✅ Icon generated: {icns_path}")


if __name__ == "__main__":
    main()
