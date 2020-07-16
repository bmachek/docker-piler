# Mailpiler as Docker

[Piler](http://www.mailpiler.org/wiki/current:index) is a feature rich open source email archiving solution. This is a project to package it as a docker image.

## Mailpiler as Docker

* setup multiple mailpiler instances on a single server
* easy, fast and reproducible setup
* easy backup
* [GDPR](https://gdpr.eu/) and [DSGVO](https://dsgvo-gesetz.de/) compatible
* [Secure mail archive](https://de.wikipedia.org/wiki/E-Mail-Archivierung) according to [GoBD](https://de.wikipedia.org/wiki/Grunds%C3%A4tze_zur_ordnungsm%C3%A4%C3%9Figen_F%C3%BChrung_und_Aufbewahrung_von_B%C3%BCchern,_Aufzeichnungen_und_Unterlagen_in_elektronischer_Form_sowie_zum_Datenzugriff), [AO](https://de.wikipedia.org/wiki/Abgabenordnung) and [HGB](https://de.wikipedia.org/wiki/Handelsgesetzbuch). See this [notes](https://drive.google.com/file/d/1dfIFcDdfiA5HADR6FmxpPNeU8K-vjTaQ/view)


## How to start

1. Install mailpiler via docker
```bash
#install docker
curl -sSL https://get.docker.com/ | CHANNEL=stable sh
# start docker mailpiler instance (use port 2525 for smtp and 8025 for http)
docker run -d --restart unless-stopped --name piler-1 \
  -e PUID=$(id -u) -e PGID=$(id -g) \
 -p 2525:25 -p localhost:8025:80 \
 -v /var/piler-1-data:/var/piler \
 -v /var/piler-1-config:/etc/piler \
 -e PILER_HOST=archive.domain.com ebtc/piler
```

2. Setup reverse proxy for web interface under a different domain

Apache2:

```ini
ProxyPass / http://localhost:8025/
ProxyPassReverse / http://localhost:8025/
```

NGINX:  See this [guide](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/)
```ini
location / {
    proxy_pass http://localhost:8025/;
}
```

3. Login and change password and usernames
 + Admin Account: `admin@local`:`pilerrocks`
 + Auditor Account: `auditor@local` : `auditor`

## Update

You can update piler be pulling an updated image from docker

```bash
docker pull ebtc/piler
docker stop piler-1
docker rm piler-2
docker run -d --restart unless-stopped --name piler-1 \
  -e PUID=$(id -u) -e PGID=$(id -g) \
  -p 2525:25 -p localhost:8025:80 \
  -v /var/piler-1-data:/var/piler \
  -v /var/piler-1-config:/etc/piler \
  -e PILER_HOST=archive.domain.com ebtc/piler
```

Then login:

```bash
docker exec -it piler-1 /bin/bash
```

and follow the [instructions from piler](http://www.mailpiler.org/wiki/current:upgrade)

## Backup

Just backup the folders `/var/piler-1-data` and `/var/piler-1-config`

## Debugging

Shell access whilst the container is running:

```bash
docker exec -it piler-1 /bin/bash
```

## How to build by yourself

```bash
git clone git@github.com:ebtcorg/docker-piler.git && cd docker-piler
sudo service docker start
sudo docker build --tag pilertest:latest .
sudo docker rm --force piler-1 && true
sudo docker run -d --name piler-1 \
 -p 2525:25 -p 8025:80 \
 -v /var/piler-1-data:/var/piler \
 -v /var/piler-1-config:/etc/piler \
 -e PILER_HOST=localhost pilertest:latest
```

### Testing and rebuilding instances

```bash
docker rm piler-1
sudo docker run -d --name piler-1 \
 -e PUID=$(id -u) -e PGID=$(id -g) \
 -p 2525:25 -p localhost:8025:80 -p localhost:8026:443 \
 -v /var/piler-1-data:/var/piler \
 -v /var/piler-1-config:/etc/piler \
 -e PILER_HOST=localhost ebtc/piler:latest
docker logs piler --follow
```

## User / Group Identifiers

When using volumes (`-v` flags) permissions issues can arise between the host OS and the container, we avoid this issue by allowing you to specify the user `PUID` and group `PGID`.

Ensure any volume directories on the host are owned by the same user you specify and any permissions issues will vanish like magic.

## Supported Architectures

Our image support only `amd64` at the time, as the sphinx is only `amd64`.

## What is piler?

Email archiving provides lots of benefits to your company. Piler is a feature rich open source email archiving solution, and a viable alternative to commercial email archiving products; check out the comparison with Mailarchiva.

Piler has a nice GUI written in PHP supporting several authentication methods (AD/LDAP, SSO, Google OAuth, 2 FA, IMAP, POP3). Be sure to try the online demo!

Piler supports

* archiving and retention rules
* legal hold
* deduplication
* digital fingerprinting and verification
* full text search
* tagging emails
* view, export, restore emails
* bulk import/export messages
* audit logs
* Google Apps
* Office 365
* and many more

How does it work:

mysql: piler stores crucial metadata of the messages
sphinx: a search engine used by the gui to return the search results
file system: this is where the encrypted and compressed messages, attachments are stored
How do emails get to the archive? You configure your email server to pass a copy of emails to the piler daemon via smtp, since piler is an SMTP(-talking) daemon. Note that you don't need to create any system or virtual users or email addresses for the piler daemon to work, because it simply archives every email it receives.

When an email is received, then it's parsed, disassembled, compressed, encrypted, and finally stored in the file system: one file for every email and attachment. Also, the textual data is written to the sph_index table. The periodic indexer job reads the sph_index table, and updates the sphinx databases.

The GUI uses sphinx and mysql database to return the search results to the users.

Piler has a built-in access control to prevent a user to access other's messages. Auditors can see every archived email. Piler parses the header and extracts the From:, To: and Cc: addresses (in case of From: it only stores the first email address, since some spammers include tons of addresses in the From: field), and when a user searches for his emails then piler tries to match his email addresses against the email addresses in the messages. To sum it up, a regular user can see only the emails he sent or received.

This leads to a limitation: piler will hide an email from a user if he was (only) in the Bcc: field. This limitation has another side effect related to external mailing lists. You have to maintain which user belongs to which external mailing lists, otherwise users won't see these messages. Internal mailing lists are not a problem as long as piler can extract the membership information from openldap OR Active Directory.

Fortunately both Exchange and postfix (and probably some other MTAs, too) are able to put envelope recipients to the email, so the limitation mentioned above is solved.
