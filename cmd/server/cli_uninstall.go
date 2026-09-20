package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// rbUninstall 卸载 fan-reubah：停止并移除 systemd 服务、移除容器、关闭防火墙端口、
// 删除二进制与安装记录，可选删除应用目录。
func rbUninstall(args []string) int {
	yes, purge, keep := false, false, false
	for _, a := range args {
		switch a {
		case "-y", "--yes":
			yes = true
		case "--purge", "--delete-appdir", "--delete-data":
			purge = true
		case "--keep-appdir", "--keep-data":
			keep = true
		case "-h", "--help":
			rbUninstallUsage()
			return 0
		default:
			cliErr("未知参数: %s，使用 -h 查看帮助", a)
			return 1
		}
	}
	if os.Geteuid() != 0 {
		cliErr("请以 root 身份运行：sudo fan-reubah uninstall")
		return 1
	}
	if purge && keep {
		cliErr("--purge 与 --keep-data 不能同时使用")
		return 1
	}

	cliBanner("卸载")
	cliSep()

	if !yes && !cliConfirm("卸载将停止并移除 fan-reubah 服务与程序，是否继续", false) {
		fmt.Println(cliPaintColor("已取消卸载。", cliYellow))
		return 0
	}

	if port, ok := rbReadRecord("PORT"); ok {
		if p, err := strconv.Atoi(port); err == nil && p > 0 && p <= 65535 {
			rbMSCloseFirewallPort(p)
		}
	} else {
		rbMSCloseFirewallPort(rbDefaultPort)
	}

	if _, err := os.Stat(rbServiceFile); err == nil {
		cliDone("正在停止并移除 systemd 服务 fan-reubah ...")
		rbMSRun("systemctl", "stop", rbServiceName)
		rbMSRun("systemctl", "disable", rbServiceName)
		_ = os.Remove(rbServiceFile)
		rbMSRun("systemctl", "daemon-reload")
		rbMSRun("systemctl", "reset-failed")
	}

	if cmd, err := exec.LookPath("docker"); err == nil {
		if out, e := exec.Command(cmd, "ps", "-a", "--filter", "name="+rbBinName, "--format", "{{.Names}}").Output(); e == nil {
			for _, n := range strings.Split(strings.TrimSpace(string(out)), "\n") {
				n = strings.TrimSpace(n)
				if n == rbBinName {
					cliDone("正在移除容器 %s ...", n)
					rbMSRun(cmd, "rm", "-f", n)
				}
			}
		}
	}

	pids := make([]int, 0)
	for _, p := range rbRunningProcs() {
		pids = append(pids, p.pid)
	}
	if len(pids) > 0 {
		cliDone("正在停止 fan-reubah 进程: %v ...", pids)
		for _, pid := range pids {
			if pr, err := os.FindProcess(pid); err == nil {
				_ = pr.Signal(syscall.SIGTERM)
			}
		}
		time.Sleep(time.Second)
		for _, pid := range pids {
			if _, err := os.Stat(filepath.Join("/proc", strconv.Itoa(pid))); err == nil {
				if pr, err := os.FindProcess(pid); err == nil {
					_ = pr.Signal(syscall.SIGKILL)
				}
			}
		}
	}

	rbMSRemoveBinary()

	dataDir := rbDetectAppDir(rbDefaultAppDir)
	info, statErr := os.Stat(dataDir)
	if statErr != nil || !info.IsDir() {
		cliDone("未检测到应用目录 %s，跳过删除。", dataDir)
	} else {
		if size, err := rbMSDirSize(dataDir); err == nil {
			cliDone("检测到应用目录: %s（约 %s）", dataDir, cliHumanSize(size))
		}
		remove := false
		switch {
		case purge:
			remove = true
		case keep:
			remove = false
		case yes:
			remove = false
		default:
			remove = cliConfirm(fmt.Sprintf("是否删除应用目录 %s（完全卸载）", dataDir), true)
		}
		if remove {
			if err := os.RemoveAll(dataDir); err != nil {
				cliWarn("删除应用目录失败: %v", err)
			} else {
				cliDone("已删除应用目录 %s", dataDir)
			}
		} else {
			cliDone("已保留应用目录 %s", dataDir)
		}
	}

	_ = os.Remove(rbRecordFile)
	cliDone("已删除安装记录 %s", rbRecordFile)

	cliDone("fan-reubah 卸载完成")
	fmt.Println(cliPaintColor("如需重新安装，请重新部署（install.sh / docker compose）。", cliGrey))
	return 0
}

func rbUninstallUsage() {
	for _, line := range []string{
		"用法: fan-reubah uninstall [选项]",
		"",
		"选项:",
		"    -y, --yes        免确认，静默卸载（默认保留应用目录）",
		"    --purge          卸载时同时删除应用目录",
		"    --delete-appdir / --delete-data  同 --purge",
		"    --keep-appdir / --keep-data     卸载时保留应用目录（默认）",
		"    -h, --help       显示帮助",
		"",
		"示例:",
		"    fan-reubah uninstall -y          免确认卸载，保留应用目录",
		"    fan-reubah uninstall -y --purge  免确认卸载，并删除应用目录",
	} {
		fmt.Println(cliPaintColor(line, cliWhite))
	}
}

// rbVtracerPkgOwned 判断该文件是否由系统软件包管理（dpkg/rpm）。
// 现行版本引擎已内嵌进单文件二进制，/usr/local/bin/vtracer 仅可能是旧版遗留或
// 用户自行安装的工具；若属于系统软件包则不予删除，避免误删用户数据。
func rbVtracerPkgOwned() bool {
	if cmd, err := exec.LookPath("dpkg"); err == nil {
		if exec.Command(cmd, "-S", rbVtracerBin).Run() == nil {
			return true
		}
	}
	if cmd, err := exec.LookPath("rpm"); err == nil {
		if exec.Command(cmd, "-qf", rbVtracerBin).Run() == nil {
			return true
		}
	}
	return false
}

func rbMSRemoveBinary() {
	paths := map[string]string{"/usr/local/bin/fan-reubah": "/usr/local/bin/fan-reubah"}
	if exe, err := os.Executable(); err == nil {
		paths[exe] = exe
	}
	for _, p := range paths {
		if _, err := os.Lstat(p); err != nil {
			continue
		}
		if err := os.Remove(p); err != nil {
			cliWarn("删除二进制文件 %s 失败: %v", p, err)
		} else {
			cliDone("已删除二进制文件 %s", p)
		}
	}
	if _, err := os.Lstat(rbVtracerBin); err == nil {
		if rbVtracerPkgOwned() {
			cliWarn("检测到 %s 由系统软件包管理（dpkg/rpm），跳过删除。", rbVtracerBin)
		} else if err := os.Remove(rbVtracerBin); err != nil {
			cliWarn("删除 vtracer 引擎 %s 失败: %v", rbVtracerBin, err)
		} else {
			cliDone("已删除 vtracer 引擎 %s", rbVtracerBin)
		}
	}
}

func rbMSCloseFirewallPort(port int) {
	portStr := strconv.Itoa(port)
	if cmd, err := exec.LookPath("firewall-cmd"); err == nil {
		if out, _ := exec.Command(cmd, "--state").Output(); strings.TrimSpace(string(out)) == "running" {
			rbMSRun(cmd, "--permanent", "--remove-port="+portStr+"/tcp")
			rbMSRun(cmd, "--reload")
			cliDone("已通过 firewalld 关闭端口 %s/tcp", portStr)
			return
		}
	}
	if cmd, err := exec.LookPath("ufw"); err == nil {
		if out, _ := exec.Command(cmd, "status").Output(); strings.Contains(string(out), "active") {
			rbMSRun(cmd, "delete", "allow", portStr+"/tcp")
			cliDone("已通过 ufw 关闭端口 %s/tcp", portStr)
			return
		}
	}
	if cmd, err := exec.LookPath("iptables"); err == nil {
		if err := exec.Command(cmd, "-D", "INPUT", "-p", "tcp", "--dport", portStr, "-j", "ACCEPT").Run(); err == nil {
			cliDone("已通过 iptables 关闭端口 %s/tcp", portStr)
		}
	}
}

func rbMSRun(name string, args ...string) {
	if _, err := exec.LookPath(name); err != nil {
		return
	}
	_ = exec.Command(name, args...).Run()
}

func rbMSDirSize(path string) (int64, error) {
	var size int64
	err := filepath.Walk(path, func(_ string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() {
			size += info.Size()
		}
		return nil
	})
	return size, err
}
