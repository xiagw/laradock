settings {
    logfile = "/tmp/lsyncd.log",
    statusFile = "/tmp/lsyncd.status",
    maxDelays = 1,
    maxProcesses = 3,
    statusInterval = 1,
    insist = false,
    nodaemon = true
}

htmldir = "/var/www/html/"
targets = {
    '192.168.16.10:/var/www/html/',
    '192.168.16.11:/var/www/html/'
}

for _, target in ipairs(targets) do
    sync {
        default.rsync,
        -- delete = running,
        -- excludeFrom = '/etc/lsyncd.exclude',
        exclude = {'runtime/*', 'Runtime/*', '.svn', '.git', '.gitignore', '.gitattributes', '.idea', '*.bak', '*.log'},
        source = htmldir,
        target = target
    }
end

nginxdir = "/nginx_sites/"
nginxhosts = {
    '192.168.16.10:/nginx_sites/',
    '192.168.16.11:/nginx_sites/'
}

for _, target in ipairs(nginxhosts) do
    sync {
        default.rsync,
        exclude = {'.svn', '.git', '.gitignore', '.gitattributes', '.idea', '*.bak', '*.log'},
        source = nginxdir,
        target = target
    }
end
