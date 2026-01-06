import subprocess
import sys
import os

def run_command(command, check=True):
    """Menjalankan command dan menampilkan output"""
    try:
        process = subprocess.run(
            command,
            shell=True,
            check=check,
            text=True,
            capture_output=False
        )
        return True
    except subprocess.CalledProcessError:
        return False

def check_git_repo():
    """Cek apakah folder ini adalah git repository"""
    if not os.path.exists(os.path.join(os.getcwd(), ".git")):
        print("❌ Folder ini bukan repository git!")
        return False
    return True

def get_current_branch():
    """Dapatkan nama branch saat ini"""
    result = subprocess.run("git branch --show-current", shell=True, text=True, capture_output=True)
    return result.stdout.strip() or "master"

def do_pull():
    """Pull dari GitHub"""
    print("\n⬇️  Melakukan PULL dari GitHub...")
    if run_command("git pull origin main", check=False):
        print("✅ Pull berhasil!")
    else:
        print("⚠️  Pull gagal atau tidak ada perubahan dari remote.")

def do_push():
    """Push ke GitHub"""
    # Cek perubahan lokal
    status = subprocess.run("git status --porcelain", shell=True, text=True, capture_output=True).stdout.strip()
    
    if not status:
        print("\n✅ Tidak ada perubahan lokal untuk di-commit.")
        choice = input("Tetap ingin push (force)? (y/n): ").lower()
        if choice != 'y':
            return
    else:
        print("\n📝 Ditemukan perubahan file:")
        print(status)
        
        # Add semua file
        print("\n➕ Menambahkan semua file...")
        run_command("git add .")
        
        # Commit
        commit_msg = input("\n💬 Masukkan pesan commit: ")
        if not commit_msg.strip():
            commit_msg = "Update otomatis"
        
        print(f"\n💾 Commit: '{commit_msg}'...")
        if not run_command(f'git commit -m "{commit_msg}"', check=False):
            print("⚠️  Commit gagal atau tidak ada perubahan.")
            return

    # Push
    print("\n⬆️  Melakukan PUSH ke GitHub...")
    current_branch = get_current_branch()
    if run_command(f"git push origin {current_branch}:main"):
        print("✅ Push berhasil!")
    else:
        print("❌ Push gagal!")

def do_sync():
    """Pull dulu, lalu Push"""
    do_pull()
    do_push()

def main():
    cwd = os.getcwd()
    print(f"📂 Folder: {cwd}")
    
    if not check_git_repo():
        return
    
    print("\n" + "="*40)
    print("       GIT SYNC - Pilih Operasi")
    print("="*40)
    print("1. PULL  (Ambil update dari GitHub)")
    print("2. PUSH  (Upload perubahan ke GitHub)")
    print("3. SYNC  (Pull dulu, lalu Push)")
    print("4. Keluar")
    print("="*40)
    
    choice = input("\nPilihan (1/2/3/4): ").strip()
    
    if choice == "1":
        do_pull()
    elif choice == "2":
        do_push()
    elif choice == "3":
        do_sync()
    elif choice == "4":
        print("👋 Bye!")
    else:
        print("❌ Pilihan tidak valid!")

if __name__ == "__main__":
    main()
