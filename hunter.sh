hunt-and-update-dns
failed now in 22s
Search logs
1s
Current runner version: '2.327.1'
Runner Image Provisioner
Operating System
Runner Image
GITHUB_TOKEN Permissions
Secret source: Actions
Prepare workflow directory
Prepare all required actions
Getting action download info
Download action repository 'actions/checkout@v4' (SHA:08eba0b27e820071cde6df949e0beb9ba4906955)
Complete job name: hunt-and-update-dns
1s
Run actions/checkout@v4
Syncing repository: CrazyStrangeSue/Aura-IP-Hunter
Getting Git version info
Temporarily overriding HOME='/home/runner/work/_temp/d553426d-d4ef-4008-8bad-580dec434e34' before making global git config changes
Adding repository directory to the temporary git global config as a safe directory
/usr/bin/git config --global --add safe.directory /home/runner/work/Aura-IP-Hunter/Aura-IP-Hunter
Deleting the contents of '/home/runner/work/Aura-IP-Hunter/Aura-IP-Hunter'
Initializing the repository
Disabling automatic garbage collection
Setting up auth
Fetching the repository
Determining the checkout info
/usr/bin/git sparse-checkout disable
/usr/bin/git config --local --unset-all extensions.worktreeConfig
Checking out the ref
/usr/bin/git log -1 --format=%H
4f065a125caed6355bcdf09dcba37a23e2d4432c
15s
Run sudo apt-get update
Get:1 file:/etc/apt/apt-mirrors.txt Mirrorlist [144 B]
Hit:2 http://azure.archive.ubuntu.com/ubuntu noble InRelease
Get:6 https://packages.microsoft.com/repos/azure-cli noble InRelease [3564 B]
Get:3 http://azure.archive.ubuntu.com/ubuntu noble-updates InRelease [126 kB]
Get:7 https://packages.microsoft.com/ubuntu/24.04/prod noble InRelease [3600 B]
Get:4 http://azure.archive.ubuntu.com/ubuntu noble-backports InRelease [126 kB]
Get:5 http://azure.archive.ubuntu.com/ubuntu noble-security InRelease [126 kB]
Get:8 https://packages.microsoft.com/repos/azure-cli noble/main amd64 Packages [1497 B]
Get:9 https://packages.microsoft.com/ubuntu/24.04/prod noble/main amd64 Packages [47.2 kB]
Get:10 https://packages.microsoft.com/ubuntu/24.04/prod noble/main arm64 Packages [32.6 kB]
Get:11 http://azure.archive.ubuntu.com/ubuntu noble-updates/main amd64 Packages [1315 kB]
Get:12 http://azure.archive.ubuntu.com/ubuntu noble-updates/main Translation-en [264 kB]
Get:13 http://azure.archive.ubuntu.com/ubuntu noble-updates/main amd64 Components [164 kB]
Get:14 http://azure.archive.ubuntu.com/ubuntu noble-updates/universe amd64 Packages [1120 kB]
Get:15 http://azure.archive.ubuntu.com/ubuntu noble-updates/universe Translation-en [287 kB]
Get:16 http://azure.archive.ubuntu.com/ubuntu noble-updates/universe amd64 Components [377 kB]
Get:17 http://azure.archive.ubuntu.com/ubuntu noble-updates/restricted amd64 Packages [1650 kB]
Get:18 http://azure.archive.ubuntu.com/ubuntu noble-updates/restricted Translation-en [361 kB]
Get:19 http://azure.archive.ubuntu.com/ubuntu noble-updates/restricted amd64 Components [212 B]
Get:20 http://azure.archive.ubuntu.com/ubuntu noble-updates/multiverse amd64 Components [940 B]
Get:21 http://azure.archive.ubuntu.com/ubuntu noble-backports/main amd64 Components [7084 B]
Get:22 http://azure.archive.ubuntu.com/ubuntu noble-backports/universe amd64 Packages [28.9 kB]
Get:23 http://azure.archive.ubuntu.com/ubuntu noble-backports/universe Translation-en [17.4 kB]
Get:24 http://azure.archive.ubuntu.com/ubuntu noble-backports/universe amd64 Components [31.0 kB]
Get:25 http://azure.archive.ubuntu.com/ubuntu noble-backports/restricted amd64 Components [216 B]
Get:26 http://azure.archive.ubuntu.com/ubuntu noble-backports/multiverse amd64 Components [212 B]
Get:27 http://azure.archive.ubuntu.com/ubuntu noble-security/main amd64 Packages [1056 kB]
Get:28 http://azure.archive.ubuntu.com/ubuntu noble-security/main Translation-en [183 kB]
Get:29 http://azure.archive.ubuntu.com/ubuntu noble-security/main amd64 Components [21.6 kB]
Get:30 http://azure.archive.ubuntu.com/ubuntu noble-security/universe amd64 Packages [878 kB]
Get:31 http://azure.archive.ubuntu.com/ubuntu noble-security/universe amd64 Components [52.3 kB]
Get:32 http://azure.archive.ubuntu.com/ubuntu noble-security/restricted amd64 Packages [1566 kB]
Get:33 http://azure.archive.ubuntu.com/ubuntu noble-security/restricted Translation-en [343 kB]
Get:34 http://azure.archive.ubuntu.com/ubuntu noble-security/restricted amd64 Components [212 B]
Get:35 http://azure.archive.ubuntu.com/ubuntu noble-security/multiverse amd64 Components [212 B]
Fetched 10.2 MB in 1s (7928 kB/s)
Reading package lists...
Reading package lists...
Building dependency tree...
Reading state information...
The following NEW packages will be installed:
  whois
0 upgraded, 1 newly installed, 0 to remove and 14 not upgraded.
Need to get 51.7 kB of archives.
After this operation, 279 kB of additional disk space will be used.
Get:1 file:/etc/apt/apt-mirrors.txt Mirrorlist [144 B]
Get:2 http://azure.archive.ubuntu.com/ubuntu noble/main amd64 whois amd64 5.5.22 [51.7 kB]
Fetched 51.7 kB in 0s (477 kB/s)
Selecting previously unselected package whois.
(Reading database ... 
(Reading database ... 5%
(Reading database ... 10%
(Reading database ... 15%
(Reading database ... 20%
(Reading database ... 25%
(Reading database ... 30%
(Reading database ... 35%
(Reading database ... 40%
(Reading database ... 45%
(Reading database ... 50%
(Reading database ... 55%
(Reading database ... 60%
(Reading database ... 65%
(Reading database ... 70%
(Reading database ... 75%
(Reading database ... 80%
(Reading database ... 85%
(Reading database ... 90%
(Reading database ... 95%
(Reading database ... 100%
(Reading database ... 219989 files and directories currently installed.)
Preparing to unpack .../whois_5.5.22_amd64.deb ...
Unpacking whois (5.5.22) ...
Setting up whois (5.5.22) ...
Processing triggers for man-db (2.12.0-4build2) ...

Running kernel seems to be up-to-date.

Restarting services...

Service restarts being deferred:
 systemctl restart hosted-compute-agent.service

No containers need to be restarted.

No user sessions are running outdated binaries.

No VM guests are running outdated hypervisor (qemu) binaries on this host.
1s
Run chmod +x ./hunter.sh
[信息] 启动 Aura IP Hunter v23.0 (Dual Track Edition)...
[信息] 准备测试工具...
[信息] 工具准备就绪。
[信息] ====== 开始处理 IPv4 优选 ======
[信息] 阶段1：获取 IPv4 情报...
[信息] 获取了 1 个高质量 IPv4 IP。
[信息] 阶段2：执行 IPv4 测速...
# XIU2/CloudflareSpeedTest v2.3.4 

2025/08/13 13:32:37 ParseCIDR err invalid CIDR address: <!DOCTYPE html><html lang="en-US"><head><title>Just a moment...</title><meta http-equiv="Content-Type" content="text/html; charset=UTF-8"><meta http-equiv="X-UA-Compatible" content="IE=Edge"><meta name="robots" content="noindex
Error: Process completed with exit code 1.
0s
/usr/bin/git config --local --name-only --get-regexp http\.https\:\/\/github\.com\/\.extraheader
http.https://github.com/.extraheader
/usr/bin/git config --local --unset-all http.https://github.com/.extraheader
/usr/bin/git submodule foreach --recursive sh -c "git config --local --name-only --get-regexp 'http\.https\:\/\/github\.com\/\.extraheader' && git config --local --unset-all 'http.https://github.com/.extraheader' || :"
1s
Cleaning up orphan processes
