import os, subprocess

# 目标相对 manifest 根目录（repo 执行钩子时 cwd 即根目录）
LINKS = [
    ("u-boot",      "../../bootloader/u-boot"),
    ("kernel-6.18", "../kernel_android-17-6.18"),
]

def main(*args, **kwargs):
    root = os.getcwd()
    for name, target in LINKS:
        link = os.path.join(root, name)
        if not os.path.isdir(os.path.join(root, target)):
            print(f"[post-sync] skip {name}: target not found -> {target}")
            continue
        # -s 软链 / -f 覆盖 / -n 已是指向目录的链接时替换而非跟进
        subprocess.run(["ln", "-sfn", target, link], check=True)
        print(f"[post-sync] {name} -> {target}")
    return True

if __name__ == "__main__":
    main()
