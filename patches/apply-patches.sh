#!/bin/bash
# V8 9.3.345.11 소스 패치 스크립트
# macOS 15+ SDK 호환성 문제 해결

set -e

V8_DIR="${1:-.}"

echo "[패치] V8 소스 패치 적용 중..."

# ── 1. zlib zutil.h 패치 ──
# Classic Mac OS 잔재 fdopen 매크로가 최신 macOS SDK _stdio.h와 충돌
ZUTIL_H="$V8_DIR/third_party/zlib/zutil.h"
if [ -f "$ZUTIL_H" ]; then
    if grep -q 'define fdopen' "$ZUTIL_H"; then
        sed -i.bak '/#if defined(MACOS) || defined(TARGET_OS_MAC)/,/#endif/{
            /#if defined(MACOS) || defined(TARGET_OS_MAC)/!{
                /#  define OS_CODE  7/!{
                    /#endif/!d
                    /#endif/d
                }
            }
        }' "$ZUTIL_H"
        rm -f "${ZUTIL_H}.bak"
        echo "  [OK] zlib zutil.h fdopen 매크로 제거"
    else
        echo "  [SKIP] zlib zutil.h 이미 패치됨"
    fi
fi

# ── 2. macOS/Linux: 시스템 clang 래퍼 생성 ──
# V8 번들 clang 13이 최신 SDK의 _Float16 타입을 지원하지 않음
CLANG_DIR="$V8_DIR/third_party/llvm-build/Release+Asserts/bin"
if [ -d "$CLANG_DIR" ] && [[ "$OSTYPE" == "darwin"* ]]; then
    # 원본 백업
    if [ -f "$CLANG_DIR/clang" ] && [ ! -L "$CLANG_DIR/clang" ] && [ ! -f "$CLANG_DIR/clang.orig" ]; then
        mv "$CLANG_DIR/clang" "$CLANG_DIR/clang.orig"
    fi

    SYSTEM_CLANG=$(xcrun -f clang)
    RESOURCE_DIR=$(${SYSTEM_CLANG} -print-resource-dir)

    cat > "$CLANG_DIR/clang" << WRAPPER
#!/bin/bash
exec ${SYSTEM_CLANG} -resource-dir ${RESOURCE_DIR} -Wno-enum-constexpr-conversion "\$@"
WRAPPER
    chmod +x "$CLANG_DIR/clang"

    cat > "$CLANG_DIR/clang++" << WRAPPER
#!/bin/bash
exec ${SYSTEM_CLANG}++ -resource-dir ${RESOURCE_DIR} -Wno-enum-constexpr-conversion "\$@"
WRAPPER
    chmod +x "$CLANG_DIR/clang++"

    echo "  [OK] macOS 시스템 clang 래퍼 생성"

    # llvm-ar 심볼릭 링크 (없으면 생성)
    if [ ! -f "$CLANG_DIR/llvm-ar" ] || [ -L "$CLANG_DIR/llvm-ar" ]; then
        LLVM_AR=$(find /opt/homebrew/opt/llvm/bin /usr/local/opt/llvm/bin -name llvm-ar 2>/dev/null | head -1)
        if [ -z "$LLVM_AR" ]; then
            # brew에 없으면 설치
            brew install llvm 2>/dev/null || true
            LLVM_AR=$(find /opt/homebrew/opt/llvm/bin /usr/local/opt/llvm/bin -name llvm-ar 2>/dev/null | head -1)
        fi
        if [ -n "$LLVM_AR" ]; then
            ln -sf "$LLVM_AR" "$CLANG_DIR/llvm-ar"
            echo "  [OK] llvm-ar 심볼릭 링크 생성"
        fi
    fi
fi

# ── 3. Linux: 시스템 clang 래퍼 생성 ──
if [ -d "$CLANG_DIR" ] && [[ "$OSTYPE" == "linux"* ]]; then
    if [ -f "$CLANG_DIR/clang" ] && [ ! -L "$CLANG_DIR/clang" ] && [ ! -f "$CLANG_DIR/clang.orig" ]; then
        mv "$CLANG_DIR/clang" "$CLANG_DIR/clang.orig"
    fi

    SYSTEM_CLANG=$(which clang 2>/dev/null || echo "/usr/bin/clang")
    SYSTEM_CLANGPP=$(which clang++ 2>/dev/null || echo "/usr/bin/clang++")

    cat > "$CLANG_DIR/clang" << WRAPPER
#!/bin/bash
exec ${SYSTEM_CLANG} -Wno-enum-constexpr-conversion "\$@"
WRAPPER
    chmod +x "$CLANG_DIR/clang"

    cat > "$CLANG_DIR/clang++" << WRAPPER
#!/bin/bash
exec ${SYSTEM_CLANGPP} -Wno-enum-constexpr-conversion "\$@"
WRAPPER
    chmod +x "$CLANG_DIR/clang++"

    # llvm-ar
    LLVM_AR=$(which llvm-ar 2>/dev/null || echo "")
    if [ -n "$LLVM_AR" ]; then
        ln -sf "$LLVM_AR" "$CLANG_DIR/llvm-ar"
    fi

    echo "  [OK] Linux 시스템 clang 래퍼 생성"
fi

echo "[패치] 완료"
