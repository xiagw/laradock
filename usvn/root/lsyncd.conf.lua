settings {
    logfile = "/tmp/lsyncd.log",
    statusFile = "/tmp/lsyncd.status",
    maxDelays = 1,
    maxProcesses = 1,
    statusInterval = 1,
    nodaemon = false
}

sync {
    default.rsyncssh,
    delete = running,
    host = "ubuntu@192.168.1.110",
    source = "/root/tool/svn_checkout/repo-test/",
    targetdir = "/tmp/repo-test/",
    excludeFrom = "/root/tool/rsync.exclude.conf",
    exclude = {'.svn', '.git', '.gitignore', '.gitattributes', '.idea', '*.bak', '*.log'},
    rsync = {
        binary = "/usr/bin/rsync",
        compress = true,
        _extra = {"--bwlimit=20000"}
    },
    ssh = {
        port = 22
    }
}