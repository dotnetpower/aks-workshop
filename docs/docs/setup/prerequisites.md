# 사전 필요 환경

## Ubuntu 기준 환경 설정 방법

### Azure CLI 설치

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

### AKS CLI 설치

```bash
sudo az aks install-cli
```

### Helm 설치

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### VS Code 설치 (WSL이나 로컬 환경인 경우)

```bash
sudo apt-get install wget gpg
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
rm -f packages.microsoft.gpg

sudo apt install apt-transport-https
sudo apt update
sudo apt install code
```

## SSH Server 설정

윈도우 사용자가 vscode remote를 이용해서 작업하기 위한 환경입니다.

### Ubuntu에서 SSH Server 설치

```bash
sudo apt-get install openssh-server
sudo apt-get install sshfs
```

### Windows에서 SSH 키 생성

```cmd
ssh-keygen -t rsa -b 4096 -f %userprofile%\.ssh\linux_rsa
scp %userprofile%\.ssh\linux_rsa.pub -i <pem_file_path> dotnetpower@<remote_ip>:~/
```

PowerShell을 사용하는 경우:

```powershell
ssh-keygen -m PEM -t rsa -b 2048
```

### Ubuntu에서 SSH 설정

```bash
sudo cat linux_rsa.pub >> ~/.ssh/authorized_keys
sudo nano /etc/ssh/sshd_config
# sshd_config 파일 중 AllowTcpForwarding yes 주석 해제
sudo systemctl restart sshd
```

### 접속 테스트

Windows cmd에서:

```cmd
ssh -i %userprofile%/.ssh/linux_rsa user_id@<remote_ip>
```

VS Code의 Remote Explorer extension을 설치하여 리모트 서버에 접속합니다.

:::warning 주의
Azure VM의 경우 SSH port open 시간이 짧아서 JIT open을 주기적으로 해야 합니다.
:::
