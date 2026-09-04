#!/usr/bin/env python3
"""MSYS2 패키지의 .pc 파일 prefix 를 실제 sysroot 경로로 고친다.

MSYS2 패키지는 /mingw64 에 설치된다고 가정하고 만들어져 있어서,
그대로 두면 pkg-config 가 존재하지 않는 경로를 돌려준다.
"""
import glob
import os
import re
import sys

ROOT = os.path.expanduser("~/.local/mingw/deps/sysroot/mingw64")
PC_DIR = os.path.join(ROOT, "lib", "pkgconfig")

changed = 0
for path in glob.glob(os.path.join(PC_DIR, "*.pc")):
    src = open(path).read()
    out = re.sub(r"^prefix\s*=\s*/mingw64\s*$", f"prefix={ROOT}", src, flags=re.M)
    # 일부 패키지는 절대경로를 본문에 박아둔다
    out = out.replace("/mingw64/include", f"{ROOT}/include")
    out = out.replace("/mingw64/lib", f"{ROOT}/lib")
    if out != src:
        open(path, "w").write(out)
        changed += 1

print(f"수정한 .pc 파일: {changed}")

# freetype2 는 harfbuzz 를 Requires.private 로 걸어두는데, harfbuzz 는 다시
# glib -> pcre2 -> ... 로 이어진다. ScummVM 은 harfbuzz 를 쓰지 않으므로
# 정적 링크 의존성에서 떼어내 사슬을 끊는다.
ft = os.path.join(PC_DIR, "freetype2.pc")
if os.path.exists(ft):
    src = open(ft).read()
    out = re.sub(r"^(Requires\.private:.*)$",
                 lambda m: m.group(1).replace("harfbuzz >=  2.0.0,", "")
                                     .replace("harfbuzz >= 2.0.0,", "")
                                     .replace(", harfbuzz", ""),
                 src, flags=re.M)
    if out != src:
        open(ft, "w").write(out)
        print("freetype2.pc: harfbuzz 의존성 제거")
