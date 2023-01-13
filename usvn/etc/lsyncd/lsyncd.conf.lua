settings {
    logfile = "/tmp/lsyncd.log",
    statusFile = "/tmp/lsyncd.status",
    maxDelays = 1,
    maxProcesses = 3,
    statusInterval = 1,
    insist = true,
    nodaemon = false
}

htmldir = "/root/docker/html/"
targets = {
    -- '172.16.0.2:/root/docker/html/',
}

for _, target in ipairs(targets) do
    sync {
        default.rsync,
        -- delete = running,
        -- excludeFrom = '/root/lsyncd.exclude',
        exclude = {'runtime/*', 'Runtime/*', '.svn', '.git', '.gitignore', '.gitattributes', '.idea', '*.bak', '*.log'},
        source = htmldir,
        target = target
    }
end

nginxdir = "/root/docker/laradock/nginx/sites/"
nginxhosts = {
    -- '192.168.16.2:/root/docker/laradock/nginx/sites/',
}

for _, target in ipairs(nginxhosts) do
    sync {
        default.rsync,
        exclude = {'.svn', '.git', '.gitignore', '.gitattributes', '.idea', '*.bak', '*.log'},
        source = nginxdir,
        target = target
    }
end
