Linux Install: curl -fsSL https://github.com/wjadams17/Fail2Ban/releases/latest/download/fail2ban_install.sh | sudo bash

sudo systemctl status fail2ban
sudo service fail2ban status

sudo fail2ban-client set sshd banip 1.2.3.4
sudo fail2ban-client set sshd unbanip 1.2.3.4
