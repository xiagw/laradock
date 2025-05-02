settings {
    logfile = "/tmp/lsyncd.log",
    statusFile = "/tmp/lsyncd.status",
    maxDelays = 1,
    maxProcesses = 10,
    statusInterval = 1,
    insist = true,
    nodaemon = false
}

htmldir = "/root/docker/html/"
htmlhosts = {
    -- '172.16.0.2:/root/docker/html/',
}
for _, target in ipairs(htmlhosts) do
sync {
    default.rsync,
    rsync = {
        -- verbose = true,
        _extra = {"--recursive"},
        -- archive = true,
        -- recursive = true,
        -- update = true,
        -- links = true,
        -- times = true,
        -- owner = true,
        -- group = true,
        -- permissions = true,
        -- sparse = true,
        -- hard_links = true,
        -- block_size = 1024,
        -- block_list = true,
        -- inplace = true,
        -- itemize_changes = true,
        -- delete_excluded = true,
        -- delete_after = true,
        -- delete_during = true,
        -- delete_befor = true,
        -- whole_file = true,
        -- dry_run = true,
        compress = true
    },
        -- delete = running,
        -- excludeFrom = '/root/lsyncd.exclude',
        exclude = {'runtime/*', 'Runtime/*', '.svn', '.git', '.gitignore', '.gitattributes', '.idea', '*.bak', '*.log'},
        source = htmldir,
        target = target
    }
end

nginxdir = "/root/docker/laradock/nginx/"
nginxhosts = {
    -- '192.168.16.2:/root/docker/laradock/nginx/',
}
for _, target in ipairs(nginxhosts) do
    sync {
        default.rsync,
        rsync = { archive = true },
        -- exclude = {'ssl/', '*.key', '.svn', '.git', '.gitignore', '.gitattributes', '.idea', '*.bak', '*.log'},
        exclude = {'.svn', '.git', '.gitignore', '.gitattributes', '.idea', '*.bak', '*.log'},
        source = nginxdir,
        target = target
}
end
