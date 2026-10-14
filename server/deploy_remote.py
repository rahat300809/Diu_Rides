import paramiko
import sys
import time

sys.stdout.reconfigure(encoding='utf-8')

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
print("Connecting to rahat@192.168.0.114...")
ssh.connect('192.168.0.114', username='rahat', password='rahat', timeout=10)
print("Connected successfully!\n")

def run(cmd, desc=''):
    print(f"==================================================")
    print(f"🚀 {desc or cmd}")
    print(f"==================================================")
    stdin, stdout, stderr = ssh.exec_command(cmd)
    out = stdout.read().decode('utf-8', errors='replace')
    err = stderr.read().decode('utf-8', errors='replace')
    if out.strip():
        print(out.strip())
    if err.strip():
        print(f"[STDERR]: {err.strip()}")
    print()
    return out

# 1. Back up database and existing completed trips
run('mkdir -p /home/rahat/backups && cp -r /home/rahat/diu_ride/server/rides.db* /home/rahat/backups/ 2>/dev/null || true', '1. Backing up SQLite database')
run('cp /home/rahat/diu_ride/server/completed_trips.csv /home/rahat/backups/completed_trips.csv.bak 2>/dev/null || true', '2. Backing up completed trips CSV')

# 2. Sync to latest origin/main
run('cd /home/rahat/diu_ride && git stash && git fetch origin && git checkout -B main origin/main && git branch -u origin/main main && git log -n 2 --oneline', '3. Syncing repo to origin/main')

# 3. Preserve trips
merge_script = """
import os
bak = '/home/rahat/backups/completed_trips.csv.bak'
cur = '/home/rahat/diu_ride/server/completed_trips.csv'
if os.path.exists(bak) and os.path.exists(cur):
    with open(bak, 'r', encoding='utf-8') as f:
        bak_lines = [l for l in f.read().splitlines() if l.strip()]
    with open(cur, 'r', encoding='utf-8') as f:
        cur_lines = [l for l in f.read().splitlines() if l.strip()]
    cur_set = set(cur_lines)
    added = 0
    with open(cur, 'a', encoding='utf-8') as f:
        for line in bak_lines:
            if line not in cur_set:
                f.write(line + '\\n')
                added += 1
    print(f'Preserved and merged {added} trips from backup.')
"""
run(f"python3 -c \"{merge_script}\"", '4. Merging runtime completed trips')

# 4. Pip install requirements
run('/home/rahat/diu_ride_env/bin/pip install -r /home/rahat/diu_ride/server/requirements.txt', '5. Installing Python dependencies')

# 5. Restart service
run('echo rahat | sudo -S systemctl restart diu-ride.service', '6. Restarting diu-ride.service')

time.sleep(3)

# 6. Check status
run('systemctl status diu-ride.service --no-pager', '7. Checking diu-ride.service status')

# 7. Test endpoints
run('curl -s http://127.0.0.1:8001/ride/health', '8. Testing /ride/health')
run('curl -s http://127.0.0.1:8001/health', '9. Testing /health')
run('curl -s -I http://127.0.0.1:8001/ride/ | head -n 12', '10. Testing /ride/ web header')

ssh.close()
print("🎉 Deployment process finished!")
