#!/bin/bash
# 依赖检查脚本：验证业务模块之间零交叉依赖
#
# 规则：
# 1. lib/features/<module>/ 下的业务模块不能 import 其他业务模块（lib/features/<other>/）
# 2. 业务模块可以 import 同目录下的文件（自己的副本）
# 3. 业务模块可以 import dart:、package:（第三方包）、lib/core/（框架代码）
# 4. UI 页面（epub_tools_page.dart 等）可以 import 业务模块
#
# 用法：bash tool/check_dependencies.sh
# 退出码：0 = 通过，1 = 有违规

cd /Users/aaa/Documents/github/epub-gadget/flutter

# 业务模块列表（排除 UI 容器和非业务功能页面）
BUSINESS_MODULES=$(ls -d lib/features/*/ | xargs -n1 basename | grep -vE '^(epub_tools|dashboard|metadata|send_to_kindle|tutorial|txt2epub|shared)$')

VIOLATIONS=0

echo "=== 检查业务模块间交叉依赖 ==="
echo ""

for mod in $BUSINESS_MODULES; do
  # 检查该模块下所有 .dart 文件的 import
  for f in lib/features/$mod/*.dart; do
    [ -f "$f" ] || continue
    filename=$(basename "$f")

    # 检查是否 import 了其他业务模块
    while IFS= read -r line; do
      # 提取 import 路径
      imp=$(echo "$line" | sed "s|import '||;s|';.*||")

      # 跳过 dart:、package:、相对路径到 core/ 或 shared/
      case "$imp" in
        dart:*) continue ;;
        package:*)
          # 检查是否 import 了另一个业务模块
          # package:epub_gadget/features/<other>/...
          other_mod=$(echo "$imp" | sed 's|package:epub_gadget/features/||' | cut -d'/' -f1)
          if [ "$other_mod" != "$mod" ] && echo "$BUSINESS_MODULES" | grep -qw "$other_mod" 2>/dev/null; then
            echo "  ✗ 违规: $mod/$filename → import 了 $other_mod ($imp)"
            VIOLATIONS=$((VIOLATIONS + 1))
          fi
          continue ;;
        ../*)
          # 相对路径 ../<other>/ → 检查是否指向另一个业务模块
          other_mod=$(echo "$imp" | sed 's|\.\./||' | cut -d'/' -f1)
          if [ "$other_mod" != "$mod" ] && echo "$BUSINESS_MODULES" | grep -qw "$other_mod" 2>/dev/null; then
            echo "  ✗ 违规: $mod/$filename → import 了 ../$other_mod/ ($imp)"
            VIOLATIONS=$((VIOLATIONS + 1))
          fi
          continue ;;
        *)
          # 同目录引用（如 'epub_image_helper.dart'）—— OK
          continue ;;
      esac
    done < <(grep "^import '" "$f" 2>/dev/null)
  done
done

echo ""
if [ $VIOLATIONS -eq 0 ]; then
  echo "✓ 通过：业务模块间零交叉依赖"
  exit 0
else
  echo "✗ 失败：发现 $VIOLATIONS 处交叉依赖违规"
  exit 1
fi
