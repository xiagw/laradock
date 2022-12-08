<?php

echo "</br>Test Redis connection... </br>";
$redis = new Redis();
$response = 'default value';
// redis host port
$redis->connect('redis',6379);
// redis password
$redis->auth('ENV_REDIS_PASSWORD');
$redis->set('foo', 'bar');
$response = $redis->get('foo');
echo "Key foo: $response" ;

echo "</br>Test MySQL connection... </br>";
// mysql user
$username = "ENV_MYSQL_USER";
// mysql password
$passwd = "ENV_MYSQL_PASSWORD";
// mysql hosts port
$arr_dns = array(
    "mysql"
);
if (!defined('MYSQLI_OPT_READ_TIMEOUT')) {
    define ('MYSQLI_OPT_READ_TIMEOUT', 5);
}
foreach ($arr_dns as $dns) {
    //create the object
    $connection = mysqli_init();
    //specify the connection timeout
    $connection->options(MYSQLI_OPT_CONNECT_TIMEOUT, 5);
    //specify the read timeout
    $connection->options(MYSQLI_OPT_READ_TIMEOUT, 5);
    //initiate the connection to the server, using both previously specified timeouts
    // $connection = mysqli_connect($dns,$username,$passwd);
    if(mysqli_real_connect($connection,$dns,$username,$passwd)){
        echo "</br> connect $dns: OK. </br>";
    }else{
        // die("connection Failed:" . mysqli_connect_errno());
        echo "</br> connect $dns: Failed </br>";
    }
    mysqli_close($connection);
}

