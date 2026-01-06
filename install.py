#!/usr/bin/env python3
import os
import subprocess
import sys
import argparse
import json

# Configuration
PROCESSES_TO_KILL = ["dart", "flutter", "adb"]

def get_adb_path():
    """Find adb.exe in common locations if not in PATH"""
    # 1. Try system PATH
    try:
        if os.name == 'nt':
            subprocess.run(["adb", "--version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            return "adb"
        else:
            subprocess.run(["adb", "--version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            return "adb"
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    # 2. Try common Android SDK locations
    if os.name == 'nt':
        local_appdata = os.environ.get('LOCALAPPDATA', '')
        common_paths = [
            os.path.join(local_appdata, 'Android', 'Sdk', 'platform-tools', 'adb.exe'),
            os.path.join(os.environ.get('USERPROFILE', ''), 'AppData', 'Local', 'Android', 'Sdk', 'platform-tools', 'adb.exe'),
            "C:\\Android\\sdk\\platform-tools\\adb.exe",
        ]
        for path in common_paths:
            if os.path.exists(path):
                return f'"{path}"'
    
    return "adb" # Fallback to PATH

def kill_process(process_name):
    """Kill a process by name if it's running (Cross-platform)"""
    try:
        # Determine process name based on OS
        target_name = process_name
        if os.name == 'nt':
            if not target_name.endswith('.exe'):
                target_name += '.exe'
            cmd = f"taskkill /F /IM {target_name}"
        else:
            # Unix/Linux/Mac
            if target_name.endswith('.exe'):
                target_name = target_name[:-4]
            cmd = f"pkill -f {target_name}"

        # Run silently
        subprocess.run(cmd, shell=True, stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
    except:
        pass

def toggle_explorer(enable=True):
    """Restart or Restore Windows Explorer to clear file locks"""
    if os.name != 'nt':
        return
        
    try:
        if enable:
            print("🖥️ Starting Explorer...")
            subprocess.Popen("explorer.exe")
        else:
            print("🚫 Killing Explorer to release file locks...")
            subprocess.run("taskkill /f /im explorer.exe", shell=True, stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
    except Exception as e:
        print(f"Explorer toggle error: {e}")

def run_command_safe(command):
    """Run a single shell command safe"""
    print(f"\n⚡ Executing: {command}")
    try:
        use_shell = True
        result = subprocess.run(
            command,
            shell=use_shell,
            check=True
        )
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ Error executing {command}: Exit code {e.returncode}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {str(e)}")
        return False

def get_connected_devices():
    """Get list of connected devices using flutter devices --machine"""
    try:
        result = subprocess.run("flutter devices --machine", shell=True, capture_output=True, text=True)
        if result.returncode == 0:
            return json.loads(result.stdout)
    except:
        pass
    return []

def run_flutter_commands(directory, device_id=None, skip_build=False):
    """Run Flutter commands in the specified directory"""
    try:
        # Pre-emptive cleanup
        print("🧹 Cleaning up lingering processes...")
        for proc in PROCESSES_TO_KILL:
            kill_process(proc)
        
        # Resolve absolute path
        abs_dir = os.path.abspath(directory)
        
        # Change to the target directory
        if not os.path.exists(abs_dir):
            print(f"Error: Directory not found - {abs_dir}")
            return False
            
        os.chdir(abs_dir)
        print(f"Changed to directory: {os.getcwd()}")
        
        if not skip_build:
            # Step 1: Maintenance & Build Prep
            prep_commands = [
                "flutter clean",
                "flutter pub get",
                "dart fix --apply",
            ]
            for cmd in prep_commands:
                if not run_command_safe(cmd):
                    return False

            # Step 2: Build Release APK
            print("\n🔨 Building Release APK...")
            if not run_command_safe("flutter build apk --release --no-tree-shake-icons"):
                return False
        else:
            print("\n⏩ Skipping build steps as requested.")

        target_device = device_id
        if not target_device:
            while True:
                print("\n🔍 Checking for connected devices...")
                devices = get_connected_devices()
                
                if len(devices) == 0:
                    print("⚠️ No devices detected.")
                    choice = input("\nEnter 'r' to refresh, or 's' to skip install: ").strip().lower()
                    if choice == 'r':
                        continue
                    break
                elif len(devices) == 1:
                    target_device = devices[0]['id']
                    print(f"📱 Detected device: {devices[0]['name']} ({target_device})")
                    choice = input(f"Install on this device? [Y/n/r] (r=refresh): ").strip().lower()
                    if choice == 'n' or choice == 's':
                        target_device = None
                        break
                    elif choice == 'r':
                        target_device = None
                        continue
                    # Default is Yes
                    break
                else:
                    print("\nMultiple devices found:")
                    for i, dev in enumerate(devices):
                        print(f"{i+1}. {dev['name']} ({dev['id']}) - {dev['targetPlatform']}")
                    
                    choice = input(f"\nChoose device (1-{len(devices)}), 'r' to refresh, or 's' to skip install: ").strip().lower()
                    if choice == 's':
                        target_device = None
                        break
                    if choice == 'r':
                        continue
                        
                    try:
                        idx = int(choice) - 1
                        if 0 <= idx < len(devices):
                            target_device = devices[idx]['id']
                            break
                    except ValueError:
                        pass
                    print(f"Invalid choice. Please enter 1-{len(devices)}, 'r', or 's'.")

        if target_device:
            # Step 4: Special Windows Handling (Kill Explorer)
            toggle_explorer(enable=False)
            
            # Step 5: Install
            install_cmd = f"flutter install -d {target_device}"
            
            # Run install
            print(f"\n📲 Installing Release APK to {target_device}...")
            install_success = run_command_safe(install_cmd)
            
            # Step 6: Restore Explorer
            toggle_explorer(enable=True)
            
            if not install_success:
                 print("⚠️ Install failed (but Explorer restored).")
            
        else:
            print("ℹ️ Skipping install step.")
            print("💡 Tip: Release APK file is located in build/app/outputs/flutter-apk/")

        print("\n✅ All tasks completed!")
        return True
        
    except Exception as e:
        print(f"Error: {str(e)}")
        # Safety net: ensure explorer is back if crash happens
        if os.name == 'nt':
             subprocess.Popen("explorer.exe")
        return False

def main():
    parser = argparse.ArgumentParser(description="Flutter Project Cleaner and Installer")
    parser.add_argument("-p", "--project", choices=['1', '2', '3', 'scanai', 'posai', 'readai'], 
                        help="Choose project: 1/scanai, 2/posai, or 3/readai")
    parser.add_argument("-d", "--custom_dir", help="Specify custom project directory path")
    parser.add_argument("-id", "--install_device", help="Specify device ID for flutter install (e.g. emulator-5554)")
    parser.add_argument("-sb", "--skip_build", action="store_true", help="Skip the build process and go straight to install")
    
    args = parser.parse_args()
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Path Resolution - Cross Platform
    scanai_path = os.path.join(script_dir, "Mobapps", "ScanAI")
    posai_path = os.path.join(script_dir, "Mobapps", "posAI")
    readai_path = os.path.join(script_dir, "Mobapps", "ReadAI_v2")
    
    directory = None
    
    if args.custom_dir:
        directory = args.custom_dir
    elif args.project:
        if args.project in ['1', 'scanai']:
            directory = scanai_path
        elif args.project in ['2', 'posai']:
            directory = posai_path
        elif args.project in ['3', 'readai']:
            directory = readai_path
    else:
        # Interactive Mode
        print("Flutter Project Cleaner and Installer")
        print("==================================")
        print("\nChoose project directory:")
        print(f"1. ScanAI ({scanai_path})")
        print(f"2. PosAI ({posai_path})")
        print(f"3. ReadAI ({readai_path})")
        print("\nTip: Append 's' to skip build (e.g., '1s')")
        
        while True:
            choice = input("\nEnter your choice (1, 2, or 3): ").strip().lower()
            if 's' in choice:
                args.skip_build = True
                choice = choice.replace('s', '')
                
            if choice == "1":
                directory = scanai_path
                break
            elif choice == "2":
                directory = posai_path
                break
            elif choice == "3":
                directory = readai_path
                break
            else:
                print("Invalid choice. Please enter 1, 2, or 3.")
    
    if directory:
        print(f"Target Directory: {directory}")
        if args.install_device:
            print(f"Target Device: {args.install_device}")
            
        success = run_flutter_commands(directory, args.install_device, args.skip_build)
        if success:
            print("\nProcess completed successfully!")
            sys.exit(0)
        else:
            print("\nProcess completed with errors.")
            sys.exit(1)

if __name__ == "__main__":
    main()
