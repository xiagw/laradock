<?php

$redis = new Redis();
$response = 'default value';
$redis->connect('redis',6379);
$redis->auth('ENV_REDIS_PASSWORD');
$redis->set('foo', rand(1,1000000));
$response = $redis->get('foo');
echo "Test Redis ... </br>\n";
echo "Redis key foo(random): $response </br>\n";

$username = "ENV_MYSQL_USER";
$passwd = "ENV_MYSQL_PASSWORD";
$arr_dns = array("mysql");
if (!defined('MYSQLI_OPT_READ_TIMEOUT')) {
    define ('MYSQLI_OPT_READ_TIMEOUT', 5);
}
// PHP 7.4 以上支持 MySQL 8.*，否则不支持
echo "Test MySQL ... </br>\n";
foreach ($arr_dns as $dns) {
    $connection = mysqli_init();
    $connection->options(MYSQLI_OPT_CONNECT_TIMEOUT, 5);
    $connection->options(MYSQLI_OPT_READ_TIMEOUT, 5);
    // $connection = mysqli_connect($dns,$username,$passwd);
    if(mysqli_real_connect($connection,$dns,$username,$passwd)){
        echo "Connect mysql:    OK. </br>\n";
    } else {
        // die("connection Failed:" . mysqli_connect_errno());
        echo "Connect mysql:    Fail. </br>\n";
    }
    mysqli_close($connection);
}

