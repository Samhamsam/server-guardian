# Server Guardian script

Settings are in the top of the server-guardian file. Watches cpu, ram, services and disk space of server.

## Install
- Copy repository to location of your preference.
```
cd /etc/
sudo git clone https://github.com/Samhamsam/server-guardian.git
```
- Make the script executable.
```
chmod +x server-guardian.sh
```
- Make hard link
```
ln /etc/server-guardian/server-guardian /usr/bin/
```
- Add script to crontab. 
```
crontab -e

Put:
*/5 * * * * server-guardian.sh -wr -wc -wh
```
