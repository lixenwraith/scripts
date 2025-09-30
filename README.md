# scripts

Common bash/pthon scripts I use across my projects, built around FreeBSD server use.

- make.sh : Go make script to facilitate multi-platform build.
- install-service.sh : install an executable as service on FreeBSD, creating config, log directories, and rc.d script, and sets the permissions.
- uninstall-service.sh : reverses previous script.
- install-app.sh : install an executable as an app, creating config, log directories, and sets up permissions.
- uninstall-app.sh : reverses previous script.
- dbprint-sqlite3.py : prints all the content of a sqlite db file.
- linecount-go.py : line countes of Go files in the current direcotry and sub-directories.
