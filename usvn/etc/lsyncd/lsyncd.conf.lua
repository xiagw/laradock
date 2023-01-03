settings {
    logfile = "/tmp/lsyncd.log",
    statusFile = "/tmp/lsyncd.status",
    maxDelays = 1,
    maxProcesses = 3,
    statusInterval = 1,
    insist = true,
    nodaemon = true
}

targets = {'172.31.0.119:/home/ubuntu/docker/html/', '172.31.0.251:/home/ubuntu/docker/html/',
           '172.31.0.177:/home/ubuntu/docker/html/'}

for _, target in ipairs(targets) do
    sync {
        default.rsync,
        -- delete = running,
        exclude = {'runtime/*', 'Runtime/*', '.svn', '.git', '.gitignore', '.gitattributes', '.idea', '*.bak', '*.log'},
        source = '/home/ubuntu/docker/html/',
        -- excludeFrom = '/home/ubuntu/lsyncd.exclude',
        target = target
    }
end
